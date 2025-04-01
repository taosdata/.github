const core = require('@actions/core');
const github = require('@actions/github');

async function run() {
    try {
        const token = core.getInput('github-token');
        const octokit = github.getOctokit(token);

        const teamLabelMap = {
            'platform': 'team platform',
            'application-aloud': 'team application',
            'application-tdasset': 'team application',
            'engine-query': 'team engine',
            'engine-storage': 'team engine',
            'tools-connectors': 'team tools',
            'tools-taosx': 'team tools',
        };

        const pr = github.context.payload.pull_request;

        if (!pr) {
            core.info('This workflow was not triggered by a pull request.');
            return;
        }

        core.info(`Processing PR #${pr.number} by ${pr.user.login}`);

        if (pr.user.type === 'Bot') {
            core.info(`Skipping bot PR #${pr.number}`);
            return;
        }

        const { data: permission } = await octokit.rest.repos.getCollaboratorPermissionLevel({
            owner: github.context.repo.owner,
            repo: github.context.repo.repo,
            username: pr.user.login,
        });

        core.info(`User ${pr.user.login} permission: ${permission.permission}`);

        if (permission.permission === 'none') {
            core.info(`User ${pr.user.login} is not a collaborator`);
            return;
        }

        let labelAdded = false;

        const { data: allTeams } = await octokit.rest.teams.list({
            org: github.context.repo.owner,
        });

        const filteredTeams = allTeams.filter(team => team.slug !== 'all');
        core.info(`Found ${filteredTeams.length} teams in the organization after filtering out 'all'.`);

        const userTeams = [];

        for (const team of filteredTeams) {
            try {
                const { data: membership } = await octokit.rest.teams.getMembershipForUserInOrg({
                    org: github.context.repo.owner,
                    team_slug: team.slug,
                    username: pr.user.login,
                });

                if (membership.state === 'active') {
                    userTeams.push(team);
                    core.info(`User ${pr.user.login} is a member of team: ${team.slug}`);
                }
            } catch (error) {
                if (error.status === 404) {
                    core.info(`User ${pr.user.login} is not a member of team: ${team.slug}`);
                } else {
                    core.error(`Error checking membership for team ${team.slug}: ${error.message}`);
                }
            }
        }

        for (const team of userTeams) {
            const teamName = team.slug;
            if (teamLabelMap[teamName]) {
                const label = teamLabelMap[teamName];
                const { data: labels } = await octokit.rest.issues.listLabelsOnIssue({
                    owner: github.context.repo.owner,
                    repo: github.context.repo.repo,
                    issue_number: pr.number,
                });

                if (!labels.some(l => l.name === label)) {
                    await octokit.rest.issues.addLabels({
                        owner: github.context.repo.owner,
                        repo: github.context.repo.repo,
                        issue_number: pr.number,
                        labels: [label],
                    });
                    core.info(`Added label '${label}' to PR #${pr.number}`);
                }
                labelAdded = true;
                break;
            }
        }

        if (!labelAdded) {
            const { data: labels } = await octokit.rest.issues.listLabelsOnIssue({
                owner: github.context.repo.owner,
                repo: github.context.repo.repo,
                issue_number: pr.number,
            });

            if (!labels.some(l => l.name === 'from community')) {
                await octokit.rest.issues.addLabels({
                    owner: github.context.repo.owner,
                    repo: github.context.repo.repo,
                    issue_number: pr.number,
                    labels: ['from community'],
                });
                core.info(`Added label 'from community' to PR #${pr.number}`);
            }
        }
    } catch (error) {
        core.setFailed(`Error processing PR: ${error.message}`);
    }
}

run();