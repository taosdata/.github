module.exports = async ({ github, context }) => {
    const teamLabelMap = {
        'platform': 'team platform',
        'application-aloud': 'team application',
        'application-tdasset': 'team application',
        'engine-query': 'team engine',
        'engine-storage': 'team engine',
        'tools-connectors': 'team tools',
        'tools-taosx': 'team tools',
    };

    const pr = context.payload.pull_request;

    if (!pr) {
        console.log('This workflow was not triggered by a pull request.');
        return;
    }

    console.log(`Processing PR #${pr.number} by ${pr.user.login}`);

    if (pr.user.type === 'Bot') {
        console.log(`Skipping bot PR #${pr.number}`);
        return;
    }

    const { data: permission } = await github.rest.repos.getCollaboratorPermissionLevel({
        owner: context.repo.owner,
        repo: context.repo.repo,
        username: pr.user.login,
    });

    console.log(`User ${pr.user.login} permission: ${permission.permission}`);

    if (permission.permission === 'none') {
        console.log(`User ${pr.user.login} is not a collaborator`);
        return;
    }

    let labelAdded = false;

    const { data: allTeams } = await github.rest.teams.list({
        org: context.repo.owner,
    });

    const filteredTeams = allTeams.filter(team => team.slug !== 'all');
    console.log(`Found ${filteredTeams.length} teams in the organization after filtering out 'all'.`);

    const userTeams = [];

    for (const team of filteredTeams) {
        try {
            const { data: membership } = await github.rest.teams.getMembershipForUserInOrg({
                org: context.repo.owner,
                team_slug: team.slug,
                username: pr.user.login,
            });

            if (membership.state === 'active') {
                userTeams.push(team);
                console.log(`User ${pr.user.login} is a member of team: ${team.slug}`);
            }
        } catch (error) {
            if (error.status === 404) {
                console.log(`User ${pr.user.login} is not a member of team: ${team.slug}`);
            } else {
                console.error(`Error checking membership for team ${team.slug}: ${error.message}`);
            }
        }
    }

    for (const team of userTeams) {
        const teamName = team.slug;
        if (teamLabelMap[teamName]) {
            const label = teamLabelMap[teamName];
            const { data: labels } = await github.rest.issues.listLabelsOnIssue({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: pr.number,
            });

            if (!labels.some(l => l.name === label)) {
                await github.rest.issues.addLabels({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    issue_number: pr.number,
                    labels: [label],
                });
                console.log(`Added label '${label}' to PR #${pr.number}`);
            }
            labelAdded = true;
            break;
        }
    }

    if (!labelAdded) {
        const { data: labels } = await github.rest.issues.listLabelsOnIssue({
            owner: context.repo.owner,
            repo: context.repo.repo,
            issue_number: pr.number,
        });

        if (!labels.some(l => l.name === 'from community')) {
            await github.rest.issues.addLabels({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: pr.number,
                labels: ['from community'],
            });
            console.log(`Added label 'from community' to PR #${pr.number}`);
        }
    }
};