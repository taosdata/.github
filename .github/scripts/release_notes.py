import json
import logging
import os
import sys
import base64
from jira import JIRA

# config logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('release-notes')

RELEASE_NOTES_TEMPLATES = {
    "tdasset_en": """
## 2. Online Internal URLs

1. TDasset: [http://192.168.3.53: 31042 /explorer](http://192.168.3.53:31042/explorer)
2. Test cases: [http://192.168.3.53: 31042 /junit/surefire.html](http://192.168.3.53:31042/junit/surefire.html) 
3. Code Coverage: [http://192.168.3.53: 31042 /coverage/index.html](http://192.168.3.53:31042/coverage/index.html)
4. REST API Definition: http://192.168.3.53:31042/swagger-ui

## 3. Installation

If it is the first installation, please follow the 1-4 steps. **Then if you install it again, please only execute step 3 and access the URL.**

1. Install the Docker Desktop environment: https://www.docker.com/products/docker-desktop/

2. Login to our internal image repository with the default account  **internaltest**
    ```
    docker login image.pre.cloud.taosdata.com -u internaltest
    ```
3. Run the following command to start the container, where the red log directory " logs " is any available empty directory locally, and the red port 6042 can be replaced with any unused port locally. Please pay special attention to the other red parts.
    a. Execute TDasset under the operating system of ARM CPU, please try the following shell command:
        ```
        docker rm tda --force && docker run -d --platform linux/arm64 -p 6042:6042 -v logs:/app/logs --name tda image.pre.cloud.taosdata.com/tda/tda:{version}
        ```
    b. Execute TDasset under a non-ARM CPU operating system, please try the following shell command:
        ```
        docker rm tda --force && docker run -d --platform linux/amd64 -p 6042:6042 -v logs:/app/logs --name tda image.pre.cloud.taosdata.com/tda/tda:{version}
        ```
    c. If you use the local data folder "data ", please add the "-v ./data:/app/data" section, which will overwrite the default test data of TDasset.
        ```
        docker rm tda --force && docker run -d --platform linux/arm64 -p 6042:6042 -v logs:/app/logs -v data:/app/data --name tda image.pre.cloud.taosdata.com/tda/tda:{version}
        ```
4. In the browser, access TDasset through the following address. The red part can be replaced with the exposed port set in the previous step.
    [http://localhost:**6042**](http://localhost:6042)"""
}


def fetch_all_issues(jira_url, jira_user, jira_token, jql):
    """get all the jira issues matched JQL condition"""
    all_issues = []
    start_at = 0
    max_results = 50
    try:
        jira = JIRA(jira_url, basic_auth=(jira_user, jira_token))
        logger.info(f"Fetching JIRA issues with JQL: {jql}")
        
        while True:
            issues = jira.search_issues(
                jql, 
                startAt=start_at, 
                maxResults=max_results
            )
            if not issues:
                break
            all_issues.extend(issues)
            start_at += len(issues)
            logger.info(f"Fetched {len(all_issues)} issues currently, next start at {start_at}")
            
        logger.info(f"Fetched {len(all_issues)} issues totally")
        return all_issues
    except Exception as e:
        logger.error(f"Failed to fetch jira issues: {e}")
        sys.exit(1)

def get_release_note(all_issues, project_name, version: str) -> str:
    """Generate release notes with new features and template content"""
    notes = ""
    new_features = {"title_en": "## 1. New Features\n", "list": []}
    notes += new_features["title_en"]
    num = 1
    for issue in all_issues:
        if (
            hasattr(issue.fields, 'customfield_12331') and
            issue.fields.customfield_12331 is not None
            and issue.fields.customfield_12331 != "-"
        ):
            notes += f"{num}. {issue.fields.customfield_12331}\n"
            num += 1
    try:
        # append the release notes template
        template_content = RELEASE_NOTES_TEMPLATES.get(f"{project_name}")
        notes += template_content.format(version=version)
    except Exception as e:
        logger.error(f"Get release note template contents failed: {e}")
        sys.exit(1)
    logger.info(f"Release notes: {notes} generated successfully for version {version}")
    return notes

def main():
    # get environment variables
    jira_url = os.environ.get('JIRA_URL')
    jira_user = os.environ.get('JIRA_USER')
    jira_token = os.environ.get('JIRA_TOKEN')
    version = os.environ.get('VERSION')
    jql = os.environ.get('JQL')
    project_name = os.environ.get('PROJECT_NAME')

    # get all issues from JIRA
    issues = fetch_all_issues(jira_url, jira_user, jira_token, jql)

    # get release notes
    release_notes = get_release_note(issues, project_name, version)
    
    # encode release notes to base64
    release_notes_b64 =  base64.b64encode(release_notes.encode('utf-8')).decode('ascii')
    
    # set GitHub Actions output
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        # base64 encoded release notes
        f.write("notes_b64<<EOF\n")
        f.write(release_notes_b64)
        f.write("\nEOF\n")
        
        # also output original notes for debugging
        f.write("notes<<EOF\n")
        f.write(release_notes)
        f.write("\nEOF\n")

if __name__ == "__main__":
    main()
