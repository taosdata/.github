#!/bin/bash
# clean_tdasset_packages.sh - Clear GitHub packages for TDasset

# define a function to show help
show_help() {
    echo "Usage: $0 -t <package_type> -n <package_name> -d <keep_days> -s <package_scope> -a <auth_token> [-v <specific_version>]"
    echo "  -t, --type        Package type (maven or npm)"
    echo "  -g, --group_id    Group ID for Maven packages"
    echo "  -n, --name        Package name"
    echo "  -d, --days        Days to keep packages (default: 10, ignored if -v is used)"
    echo "  -s, --scope       Package scope (for npm packages, default: taosdata)"
    echo "  -a, --auth        GitHub authentication token"
    echo "  -v, --version     Specific version to delete (optional)"
    echo "  -h, --help        Show this help"
    echo ""
    echo "Examples:"
    echo "  # Delete packages older than 10 days:"
    echo "  $0 -t npm -n tdasset-frontend -a token123"
    echo ""
    echo "  # Delete specific version:"
    echo "  $0 -t npm -n tdasset-frontend -a token123 -v 1.0.3-hotfix0"
    echo "  $0 -t maven -g com.taosdata.tdasset -n tdasset-backend -a token123 -v 1.0.3.0"
    exit 1
}

# initialize variables
PACKAGE_TYPE=""
GROUP_ID=""
PACKAGE_NAME=""
KEEP_DAYS=10
PACKAGE_SCOPE="taosdata"
AUTH_TOKEN=""
SPECIFIC_VERSION=""

# parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -t|--type)
            PACKAGE_TYPE="$2"
            shift
            shift
            ;;
        -g|--group_id)
            GROUP_ID="$2"
            shift
            shift
            ;;
        -n|--name)
            PACKAGE_NAME="$2"
            shift
            shift
            ;;
        -d|--days)
            KEEP_DAYS="$2"
            shift
            shift
            ;;
        -s|--scope)
            PACKAGE_SCOPE="$2"
            shift
            shift
            ;;
        -a|--auth)
            AUTH_TOKEN="$2"
            shift
            shift
            ;;
        -v|--version)
            SPECIFIC_VERSION="$2"
            shift
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# check if required parameters are set
if [ -z "$PACKAGE_TYPE" ] || [ -z "$PACKAGE_NAME" ] || [ -z "$AUTH_TOKEN" ]; then
    echo "Error: Missing required parameters."
    show_help
fi

if [ "$PACKAGE_TYPE" == "maven" ] && [ "$GROUP_ID" == "" ]; then
    echo "Error: Please input the group id for maven package."
    exit 1
fi

# Function to delete specific version
delete_specific_version() {
    local package_type="$1"
    local package_id="$2"
    local version_to_delete="$3"
    
    echo "=================================================="
    echo "Deleting specific version based on: $version_to_delete"
    
    # 根据包类型确定要删除的版本格式
    local target_version
    if [ "$package_type" == "maven" ]; then
        target_version="$version_to_delete"
        echo "Maven Package: $PACKAGE_NAME, target version: $target_version"
    else
        # NPM包删除hotfix版本，将最后的.0替换为-hotfix0
        target_version=$(echo "$version_to_delete" | sed 's/\.0$/-hotfix0/')
        echo "NPM Package: @${PACKAGE_SCOPE}/${PACKAGE_NAME}, target version: $target_version"
    fi
    echo "=================================================="
    
    # 获取所有版本列表
    if [ "$package_type" == "maven" ]; then
        ALL_VERSIONS=$(curl -s -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/taosdata/packages/maven/${package_id}/versions")
    else
        ALL_VERSIONS=$(curl -s -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/${PACKAGE_SCOPE}/packages/npm/$PACKAGE_NAME/versions")
    fi
    
    # 检查API调用是否成功
    if ! echo "$ALL_VERSIONS" | jq empty 2>/dev/null; then
        echo "Error: Invalid JSON response"
        echo "Response: $ALL_VERSIONS"
        return 1
    fi
    
    if echo "$ALL_VERSIONS" | jq -e 'type == "object" and has("message")' > /dev/null; then
        echo "Failed to fetch version list: $(echo "$ALL_VERSIONS" | jq -r '.message')"
        return 1
    fi
    
    # 查找目标版本的ID
    VERSION_ID=$(echo "$ALL_VERSIONS" | jq -r ".[] | select(.name == \"$target_version\") | .id" | head -1)
    
    if [ -z "$VERSION_ID" ] || [ "$VERSION_ID" == "null" ]; then
        echo "Version $target_version not found in package"
        return 0
    fi
    
    echo "Found target version: $target_version (ID: $VERSION_ID)"
    
    # 删除版本
    if [ "$package_type" == "maven" ]; then
        DELETE_RESPONSE=$(curl -s -L -X DELETE \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/taosdata/packages/maven/${package_id}/versions/${VERSION_ID}")
    else
        DELETE_RESPONSE=$(curl -s -L -X DELETE \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/${PACKAGE_SCOPE}/packages/npm/$PACKAGE_NAME/versions/$VERSION_ID")
    fi
    
    # 检查删除结果
    if [ -n "$DELETE_RESPONSE" ] && echo "$DELETE_RESPONSE" | jq -e 'has("message")' > /dev/null 2>&1; then
        echo "Failed to delete: $(echo "$DELETE_RESPONSE" | jq -r '.message')"
        return 1
    else
        echo "Successfully deleted version: $target_version (ID: $VERSION_ID)"
        return 0
    fi
}

# Main logic
if [ -n "$SPECIFIC_VERSION" ]; then
    # Delete specific version mode
    if [ "$PACKAGE_TYPE" == "maven" ]; then
        PACKAGE_ID="${GROUP_ID}.${PACKAGE_NAME}"
        delete_specific_version "maven" "$PACKAGE_ID" "$SPECIFIC_VERSION"
    else
        delete_specific_version "npm" "" "$SPECIFIC_VERSION"
    fi
    exit $?
fi


# get common keep days
cutoff_date=$(date -d "$KEEP_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)
echo "Using cutoff date: $cutoff_date"

# get frontend build keep days
build_cutoff_date=$(date -d "2 days ago" +%Y-%m-%dT%H:%M:%SZ)
echo "Using build cutoff date: $build_cutoff_date"

# initialize statistic number
total_count=0
deleted_count=0
skipped_count=0
release_count=0
page=1
has_more_pages=true

# output task info
echo "=================================================="
if [ "$PACKAGE_TYPE" == "maven" ]; then
    echo "Maven Package: $PACKAGE_NAME"
else
    echo "NPM Package: @${PACKAGE_SCOPE}/${PACKAGE_NAME}"
fi
echo "=================================================="

# check package type
if [ "$PACKAGE_TYPE" == "maven" ]; then
    PACKAGE_ID="${GROUP_ID}.${PACKAGE_NAME}"
    # Maven package
    while $has_more_pages; do
        echo "- Fetch $page page data..."
        
        # version list
        PAGE_RESPONSE=$(curl -s -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/taosdata/packages/maven/${PACKAGE_ID}/versions?per_page=100&page=$page")
        
        # check if it's a valid JSON file
        if ! echo "$PAGE_RESPONSE" | jq empty 2>/dev/null; then
            echo "Error: Invalid JSON response for page $page"
            echo "Response: $PAGE_RESPONSE"
            has_more_pages=false
            continue
        fi
        
        # check API response
        if echo "$PAGE_RESPONSE" | jq -e 'type == "object" and has("message")' > /dev/null; then
            echo "Failed to fetch version list: $(echo "$PAGE_RESPONSE" | jq -r '.message')"
            has_more_pages=false
            continue
        fi
        
        PAGE_VERSIONS=$(echo "$PAGE_RESPONSE" | jq -c '.')
        # check if there is more data
        versions_count=$(echo "$PAGE_VERSIONS" | jq -r '. | length')
        echo "  Found $versions_count versions in page $page"
        if [ "$versions_count" -eq 0 ]; then
            has_more_pages=false
            echo "- All page data has been obtained"
            continue
        fi
        
        total_count=$((total_count + versions_count))
        
        # version distribution
        echo "=========== Version Distribution ==========="
        echo "$PAGE_VERSIONS" | jq -r '.[].name' | sort | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | uniq -c || echo "No releases found"
        echo "==========================================="
        
        # handle version item
        while read -r version; do
            # skip empty line
            if [ -z "$version" ]; then
                continue
            fi
            
            version_id=$(echo "$version" | jq -r '.id')
            raw_version_name=$(echo "$version" | jq -r '.name')
            version_name=$(echo "$raw_version_name" | tr -d '[:space:]' | tr -d '\r\n')
            version_date=$(echo "$version" | jq -r '.updated_at')
            
            echo "DEBUG: Processing version: '$version_name' (ID: $version_id, date: $version_date)"
            
            # transfer the date as timestamp
            version_timestamp=$(date -d "$version_date" +%s 2>/dev/null || echo 0)
            cutoff_timestamp=$(date -d "$cutoff_date" +%s 2>/dev/null || echo 0)
            
            # 1. check if it's a official edition
            if [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || 
                [[ "$version_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "- Keeping release version: $version_name (ID: $version_id)"
                release_count=$((release_count + 1))
                continue
            fi
            
            # 2. check whether it's a version that is updated within the last keep days
            if [ $version_timestamp -ge $cutoff_timestamp ]; then
                echo "- Keeping recent version: $version_name (ID: $version_id, update date: $version_date)"
                skipped_count=$((skipped_count + 1))
                continue
            fi
            
            # 3. handle development and daily build edition before keep days
            if [[ "$version_name" =~ [0-9]+\.[0-9]+\.[0-9]+-[0-9]{8} ]]; then
                echo "- Deleting old daily build: $version_name (ID: $version_id, update date: $version_date)"
            elif [[ "$version_name" =~ [0-9]+\.[0-9]+\.[0-9]+-build ]]; then
                echo "- Deleting old snapshot version: $version_name (ID: $version_id, update date: $version_date)"
            else
                echo "- Deleting other old version: $version_name (ID: $version_id, update date: $version_date)"
            fi
            
            # delete the old verion
            DELETE_RESPONSE=$(curl -s -L -X DELETE \
                -H "Authorization: Bearer $AUTH_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "https://api.github.com/orgs/taosdata/packages/maven/${PACKAGE_ID}/versions/${version_id}")
            
            if [ -n "$DELETE_RESPONSE" ] && [ "$(echo "$DELETE_RESPONSE" | jq -r 'has("message")')" == "true" ]; then
                echo "  Failed to delete: $(echo "$DELETE_RESPONSE" | jq -r '.message')"
            else
                echo "Deleted successfully: $version_name (ID: $version_id)"
                deleted_count=$((deleted_count + 1))
            fi
            
            # Sleep for 0.5 seconds to avoid hitting the rate limit
            sleep 0.5
        done < <(echo "$PAGE_VERSIONS" | jq -c '.[]')
        
        # next page
        page=$((page + 1))
    done
elif [ "$PACKAGE_TYPE" == "npm" ]; then
    # NPM package
    while $has_more_pages; do
        echo "- Fetch $page page data..."
        
        # version list
        PAGE_VERSIONS=$(curl -s -L \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/orgs/${PACKAGE_SCOPE}/packages/npm/$PACKAGE_NAME/versions?per_page=100&page=$page")
        
        # check version number
        versions_count=$(echo "$PAGE_VERSIONS" | jq -r '. | length')
        echo "  Found $versions_count versions in page $page"
        
        if [ "$versions_count" -eq 0 ]; then
            has_more_pages=false
            echo "- All page data has been obtained"
            continue
        fi
        
        total_count=$((total_count + versions_count))
        
        # version distribution
        echo "=========== Version Distribution ==========="
        echo "$PAGE_VERSIONS" | jq -r '.[].name' | sort | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' | uniq -c || echo "No releases found"
        echo "==========================================="
        
        # handle version item
        while read -r version; do
            # skip empty line
            if [ -z "$version" ]; then
                continue
            fi
            
            version_id=$(echo "$version" | jq -r '.id')
            raw_version_name=$(echo "$version" | jq -r '.name')
            version_name=$(echo "$raw_version_name" | tr -d '[:space:]' | tr -d '\r\n')
            version_date=$(echo "$version" | jq -r '.updated_at')
            
            echo "Handle: '$version_name' (ID: $version_id, update date: $version_date)"
            
            # transfer date as timestamp
            version_timestamp=$(date -d "$version_date" +%s 2>/dev/null || echo 0)
            cutoff_timestamp=$(date -d "$cutoff_date" +%s 2>/dev/null || echo 0)
            build_cutoff_timestamp=$(date -d "$build_cutoff_date" +%s 2>/dev/null || echo 0)
            
            # 1. check if it's a official edition
            if [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || 
                [[ "$version_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "- Keeping release version: $version_name (ID: $version_id)"
                release_count=$((release_count + 1))
                continue
            fi
            
            # 2. check daily build version
            if [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{8}$ ]]; then
                # within keep days
                if [ $version_timestamp -ge $cutoff_timestamp ]; then
                    echo "- Keeping recent daily build: $version_name (ID: $version_id, update date: $version_date)"
                    skipped_count=$((skipped_count + 1))
                    continue
                else
                    echo "- Deleting old daily build: $version_name (ID: $version_id, update date: $version_date)"
                fi
            # 3. check build version
            elif [[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+-build-[0-9]+$ ]]; then
                # within 2 days
                if [ $version_timestamp -ge $build_cutoff_timestamp ]; then
                    echo "- Keeping recent build version: $version_name (ID: $version_id, update date: $version_date)"
                    skipped_count=$((skipped_count + 1))
                    continue
                else
                    echo "- Deleting old build version: $version_name (ID: $version_id, update date: $version_date)"
                fi
            # 4. other versions
            else
                if [ $version_timestamp -ge $cutoff_timestamp ]; then
                    echo "- Keeping other recent version: $version_name (ID: $version_id, update date: $version_date)"
                    skipped_count=$((skipped_count + 1))
                    continue
                else
                    echo "- Deleting other old version: $version_name (ID: $version_id, update date: $version_date)"
                fi
            fi
            
            # delete the old version
            echo "- Delete old version: $version_name (ID: $version_id, update date: $version_date)"
            DELETE_RESPONSE=$(curl -s -L -X DELETE \
                -H "Authorization: Bearer $AUTH_TOKEN" \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "https://api.github.com/orgs/${PACKAGE_SCOPE}/packages/npm/$PACKAGE_NAME/versions/$version_id")
            
            # check API response
            if [ -n "$DELETE_RESPONSE" ] && [ "$(echo "$DELETE_RESPONSE" | jq -e 'has("message")')" == "true" ]; then
                echo "Delete failed: $(echo "$DELETE_RESPONSE" | jq -r '.message')"
            else
                echo "Delete sucessfully: $version_name"
                deleted_count=$((deleted_count + 1))
            fi
            
            # Sleep for 0.5 seconds to avoid hitting the rate limit
            sleep 0.5
        done < <(echo "$PAGE_VERSIONS" | jq -c '.[]')
        
        # next page
        page=$((page + 1))
    done
else
    echo "Error: Unsupported package type: $PACKAGE_TYPE"
    exit 1
fi

# output summary info
echo "=================================================="
if [ "$PACKAGE_TYPE" == "maven" ]; then
    echo "Finish cleaning package $PACKAGE_NAME:"
else
    echo "Finish cleaning NPM package @${PACKAGE_SCOPE}/${PACKAGE_NAME}:"
fi
echo "- Package total count: $total_count"
echo "- Release versions kept: $release_count"
echo "- Recent versions kept: $skipped_count"
echo "- Old versions deleted: $deleted_count"
echo "=================================================="