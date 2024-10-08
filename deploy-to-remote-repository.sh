#!/bin/bash -e

# Deploy to Remote Repository Action
# See README.md

# Trivial temp directory management
SCRATCH=$(mktemp -d) || exit 1

# Cleanup the temp directory on exit
function cleanup {
	# remove the temp directory
	rm -rf "$SCRATCH"
	# Remove any ssh keys we've set
	rm -f ~/.ssh/private_key
}
trap cleanup EXIT

# Update the REMOTE_REPO_DIR to be a subdirectory of the scratch directory
REMOTE_REPO_DIR="${SCRATCH}/remote-repo"

# Store the commit message in a temporary file.
COMMIT_MESSAGE=$(git log -1 --pretty=%B)
echo "$COMMIT_MESSAGE" > "${SCRATCH}/commit.message"

# Setup the SSH key.
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Write the private key to a file, interpret any escaped newlines
if [ "${SSH_PRIVATE_KEY}" != "" ]; then
	echo -e "${SSH_PRIVATE_KEY}" > ~/.ssh/private_key
elif [ "${SSH_KEY}" != "" ]; then
	echo -e "${SSH_KEY}" > ~/.ssh/private_key
fi

chmod 600 ~/.ssh/private_key

# Clone remote repository
git clone "${REMOTE_REPO}" "${REMOTE_REPO_DIR}" --depth 1 --config init.defaultBranch="${REMOTE_BRANCH}"

# Rsync current repository to remote repository. Split the exclude list into an
# array by splitting on commas.
IFS=', ' read -r -a EXCLUDES <<< "$EXCLUDE_LIST"

# Build the rsync exclude options
EXCLUDE_OPTIONS="--exclude=.git "

for EXCLUDE in "${EXCLUDES[@]}"; do
	EXCLUDE_OPTIONS+="--exclude=${EXCLUDE} "
done

# shellcheck disable=SC2086
rsync -av $EXCLUDE_OPTIONS "${BASE_DIRECTORY}" "${REMOTE_REPO_DIR}/${DESTINATION_DIRECTORY}" --delete

# Replace .gitignore with .deployignore recursively.
if [ -f "${REMOTE_REPO_DIR}/${DESTINATION_DIRECTORY}/.deployignore" ]; then
	echo "Replacing .gitignore with .deployignore"

	find "${REMOTE_REPO_DIR}/${DESTINATION_DIRECTORY}" -type f -name '.gitignore' | while read -r GITIGNORE_FILE; do
		echo "# Emptied by deploy-to-remote-repository.sh; '.deployignore' exists and used as global .gitignore." > "$GITIGNORE_FILE"
	done

	mv -f "${REMOTE_REPO_DIR}/${DESTINATION_DIRECTORY}/.deployignore" "${REMOTE_REPO_DIR}/${DESTINATION_DIRECTORY}/.gitignore"
fi

# Commit and push changes to remote repository
cd "${REMOTE_REPO_DIR}" || exit 1

# Set git user.name to include repository name
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | awk -F '/' '{print $2}')
git config user.name "${REPO_NAME} GitHub Action"
git config user.email "action@github.com"

# Checkout or create a branch if it doesn't exist
git config alias.checkoutalt '!f() { git checkout $1 2>/dev/null || git checkout -b $1; }; f' 
git checkoutalt "${REMOTE_BRANCH}"

git add -A
git status
git commit --allow-empty -a --file="${SCRATCH}/commit.message"

echo "Pushing to ${REMOTE_REPO}@${REMOTE_BRANCH}"

# Push the new branch to the remote repository
if [ "${FORCE_PUSH}" == "true" ]; then
	git push -u -f origin "${REMOTE_BRANCH}"
else
	git push -u origin "${REMOTE_BRANCH}"
fi
