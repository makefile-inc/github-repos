# Copyright 2026
# license that can be found in the LICENSE file.

_REPOS_ROOT_DIR_WITH_SLASH := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
_REPOS_ROOT_DIR := $(_REPOS_ROOT_DIR_WITH_SLASH:/=)

include $(_REPOS_ROOT_DIR)/makefile-git-crypt/include.mk.full.inc

_GH_BINS_PLATFORM_ARCH = $(OS_CALCULATED)_$(ARCH_CALCULATED)
_GH_STORED_BINS_ARCHIVE = $(_REPOS_ROOT_DIR)/.mirror/bins_$(_GH_BINS_PLATFORM_ARCH).tar.xz
_GH_STORED_BINS_SUM = $(_REPOS_ROOT_DIR)/.mirror/bins_$(_GH_BINS_PLATFORM_ARCH).sha256sum
_GH_ORGANIZATIONS_DIR = $(CURDIR)/organizations
_GH_TEMPLATE_DIR = $(_REPOS_ROOT_DIR)/.template

define _GH_CHECK_BINARIES_INCLUDES
${_GIT_CRYPT_OP_INCLUDES} \
function check_required_binaries() {\
	local bin_dir="$(BINARIES_PATH)"; \
	local platform="$(_GH_BINS_PLATFORM_ARCH)"; \
	if [ ! -d "$$bin_dir" ]; then \
		exit_with_err "'$$bin_dir' dir not found"; \
	fi; \
	local required_bins=("git-crypt" "tofu" "$${platform}/terraform-provider-github"); \
	toggle_globs "on"; \
	for fl in $$bin_dir/**; do \
		if [ -d "$$fl" ]; then \
			continue; \
		fi; \
		local new_required=(); \
		for r_bin in "$${required_bins[@]}"; do \
			if [[ "$$fl" =~ $$r_bin ]]; then \
				continue; \
			fi; \
			new_required+=("$$r_bin"); \
		done; \
		required_bins=(); \
		for n_bin in "$${new_required[@]}"; do \
			required_bins+=("$$n_bin"); \
		done; \
	done; \
	toggle_globs; \
	if [ "$${#required_bins[@]}" -eq 0 ]; then \
		return 0; \
	fi; \
	echo_warn "Not found next required binaries: $${required_bins[*]}"; \
	return 1; \
};
endef

define _GH_SYNC_ORGS_INCLUDES
${INCLUDE_ECHO} \
function try_extract_module_dir() { \
	local passed_dir="$${1:-}"; \
	local module_dir="modules/repo"; \
	local main_f="main.tf"; \
	local direct_path="makefile-github-repos"; \
	if [ -n "$$passed_dir" ]; then \
		direct_path="$${passed_dir%/}"; \
		direct_path="$${passed_dir#$(CURDIR)/}"; \
	fi; \
	if [ -f "$(CURDIR)/$${direct_path}/$${module_dir}/$${main_f}" ]; then \
		echo -n "$$direct_path"; \
		return 0; \
	fi; \
	if [ -n "$$passed_dir" ]; then \
		echo_err "Passed makefile-inc/github-repos dir '$$passed_dir' not found or not contains repo terraform module"; \
		return 1; \
	fi; \
	local modules_file="$(CURDIR)/.gitmodules"; \
	if [ ! -f "$$modules_file" ]; then \
		echo_err "Cannot extract makefile-inc/github-repos dir. '$$modules_file' file not found and not pass dir directly"; \
		return 1; \
	fi; \
	local found_m=""; \
	if ! found_m="$$(grep -B 1 -A 1 'makefile-inc/github-repos.git' "$$modules_file")"; then \
		echo_err "Cannot extract makefile-inc/github-repos.git settings from '$$modules_file'"; \
		return 1; \
	fi; \
	local regex="\\s+path\\s+=\\s+([[:graph:]]+)"; \
	if [[ "$$found_m" =~ $$regex ]]; then \
		local path_from_m="$${BASH_REMATCH[1]}"; \
		path_from_m="$${path_from_m%/}"; \
		if [ -z "$$path_from_m" ]; then \
			echo_err "Got empty path from '$$modules_file'"; \
			return 1; \
		fi; \
		if [ -f "$(CURDIR)/$${path_from_m}/$${module_dir}/$${main_f}" ]; then \
			echo -n "$$path_from_m"; \
			return 0; \
		fi; \
		echo_err "Cannot extract makefile-inc/github-repos.git path from '$$modules_file'"; \
		return 1; \
	fi; \
	echo_err "Cannot extract makefile-inc/github-repos.git path from '$$modules_file'"; \
	return 1; \
}; \
function sync_org_with_templates() { \
	local org_dir="$$1"; \
	local module_dir="$${2:-}"; \
	if [ -z "$$org_dir" ]; then \
		exit_with_err "Org dir not passed!"; \
	fi; \
	if [ -n "$$module_dir" ]; then \
		if [[ "$$module_dir" != */ ]]; then \
			module_dir="$${module_dir}/"; \
		fi; \ 
	fi; \
	local org_name=""; \
	if ! org_name="$$(basename "$$org_dir")"; then \
		exit_with_err "Cannot extract org name from dir '$$org_dir'"; \
	fi; \
	if [ -z "$$org_name" ]; then \
		exit_with_err "Org name is empty for dir '$$org_dir'!"; \
	fi; \
	local -A sync_force=(); \
	sync_force["main.tf"]="true"; \
	if ! pushd . > /dev/null; then \
		exit_with_err "Cannot pushd current dir"; \
	fi; \
	if ! cd "$(_GH_TEMPLATE_DIR)"; then \
		exit_with_err "Cannot cd to template dir '$(_GH_TEMPLATE_DIR)'"; \
	fi; \
	local need_commit=""; \
	for tf_file in *.tf; do \
		local template_file=""; \
		if ! template_file="$$(realpath "$$tf_file")"; then \
			exit_with_err "Cannot get real path for '$$tf_file'"; \
		fi; \
		local base_template_name=""; \
		if ! base_template_name="$$(basename "$$template_file")"; then \
			exit_with_err "Cannot get base name for '$$template_file'"; \
		fi; \
		local full_file_path="$${org_dir}/$${tf_file}"; \
		if [ -f "$$full_file_path" ]; then \
			if [[ ! -v sync_force["$$base_template_name"] ]]; then \
    			echo_info "File '$$tf_file' for org '$$org_name' already exists. Skip"; \
				continue; \
			else \
				echo_warn "File '$$tf_file' for org '$$org_name' exists but will sync"; \
  			fi; \
		fi; \
		echo_info "Prepare and save '$$template_file' to '$$full_file_path' for org '$$org_name'"; \
		local -A replaces_map=(); \
		replaces_map["%%OWNER_NAME%%"]="$$org_name"; \
		replaces_map["%%MODULE_DIR%%"]="$$module_dir"; \
		if ! cp "$$template_file" "$$full_file_path"; then \
			exit_with_err "Cannot copy template file '$$template_file' to '$$full_file_path'"; \
		fi; \
		for tmp_str in "$${!replaces_map[@]}"; do \
			local tmp_val="$${replaces_map[$$tmp_str]}"; \
			if ! sed -i "s/$$tmp_str/$$tmp_val/g" "$$full_file_path"; then \
				exit_with_err "Cannot replace replace '$$tmp_str' to '$$tmp_val' in file '$$full_file_path'"; \
			fi; \
		done; \
		need_commit="true"; \
	done; \
	if ! popd > /dev/null; then \
		exit_with_err "Cannot pushd current dir"; \
	fi; \
	if [ -z "$$need_commit" ]; then \
		return 0; \
	fi; \
	return 1; \
};
endef

##@ Github repos. Mirror binaries

gh/bins/check/archive/deps: check/installed/tar check/installed/find check/installed/sha256sum

gh/bins/check/required: check/installed/find
	@${_GH_CHECK_BINARIES_INCLUDES} \
	if ! check_required_binaries; then \
		exit_with_err "Not all required binaries installed"; \
	fi; \

gh/bins/archive: gh/bins/check/archive/deps gh/bins/check/required
	@${INCLUDE_ECHO} \
	bin_dir="$(BINARIES_PATH)"; \
	tmp_archive="$(_GH_STORED_BINS_ARCHIVE).tmp"; \
	dest_archive="$(_GH_STORED_BINS_ARCHIVE)"; \
	tmp_sums_file="$(_GH_STORED_BINS_SUM).tmp"; \
	sums_file="$(_GH_STORED_BINS_SUM)"; \
	pushd .; \
	if ! cd "$$bin_dir"; then \
		exit_with_err "Cannot cd to '$$bin_dir'"; \
	fi; \
	if ! $(FIND_BIN) . -type f -exec sha256sum -b {} + > "$$tmp_sums_file"; then \
		exit_with_err "Cannot calculate binaries sha256 sum and write to temp file '$$tmp_sums_file'"; \
	fi; \
	popd; \
	$(FIND_BIN) "$$bin_dir" \( -type f -o -type d \) -printf "%P\n" | $(TAR_BIN) -cJvf "$$tmp_archive" --no-recursion -C "$$bin_dir" -T -; \
	tar_statuses=("$${PIPESTATUS[@]}"); \
	if [[ "$${tar_statuses[0]}" != "0" || "$${tar_statuses[1]}" != "0" ]]; then \
		exit_with_err "Cannot archive '$$bin_dir' to '$$tmp_archive'"; \
	fi; \
	echo_info "Replace old '$$dest_archive' on new '$$tmp_archive'"; \
	if ! rm -f "$$sums_file"; then \
		exit_with_err "Cannot remove old sum file '$$sums_file'"; \
	fi; \
	if ! mv "$$tmp_sums_file" "$$sums_file"; then \
		exit_with_err "Cannot rename temp sum file '$$tmp_sums_file' to dest '$$sums_file'"; \
	fi; \
	if ! rm -f "$$dest_archive"; then \
		exit_with_err "Cannot remove old archive '$$dest_archive'"; \
	fi; \
	if ! mv "$$tmp_archive" "$$dest_archive"; then \
		exit_with_err "Cannot rename temp archive '$$tmp_archive' to dest '$$dest_archive'"; \
	fi; \
	if ! git add "$$dest_archive" "$$sums_file"; then \
		exit_with_err "Cannot add archive '$$dest_archive' to git"; \
	fi; \
	if ! git commit -m "Upgrade binaries archive"; then \
		exit_with_err "Cannot commit archive '$$dest_archive' to git"; \
	fi; \

gh/bins/install: bin gh/bins/check/archive/deps ## Install binaries from $(_REPOS_DIR)/.mirror
	@${_GH_CHECK_BINARIES_INCLUDES} \
	if check_required_binaries; then \
		exit 0; \
	fi; \
	archive_to_extract="$(_GH_STORED_BINS_ARCHIVE)"; \
	sum_file="$(_GH_STORED_BINS_SUM)"; \
	if [ ! -f "$$sum_file" ]; then \
		exit_with_err "Sums file '$$sum_file' not found"; \
	fi; \
	if [ ! -f "$$archive_to_extract" ]; then \
		exit_with_err "Archive to install '$$archive_to_extract' not found"; \
	fi; \
	if ! $(TAR_BIN) -xvf "$$archive_to_extract" -C "$(BINARIES_PATH)"; then \
		exit_with_err "Cannot extract '$$archive_to_extract' to '$(BINARIES_PATH)'"; \
	fi; \
	pushd . > /dev/null; \
	if ! cd "$(BINARIES_PATH)"; then \
		exit_with_err "Cannot cd to '$$bin_dir'"; \
	fi; \
	if ! sha256sum -c "$$sum_file"; then \
		exit_with_err "Fail to check binaries sha256 sum"; \
	fi; \
	popd

gh/_bins/clean:
	@rm -rfv "$(BINARIES_PATH)"

gh/bins/upgrade: gh/_bins/clean gh/bins/install ## Install binaries from $(_REPOS_DIR)/.mirror

##@ Github repos. Repo itself

gh/repo/new/init: gh/bins/install gh/bins/check/required ## Init new repository after create with git-crypt
	@##~ KEY_PATH=PATH - path to save git-crypt key. Should be outside the repo (current dir)
	$(MAKE) git-crypt/repo/symmetric/init
	$(MAKE) make git-crypt/add/file FILE=*.secrets.tf
	$(MAKE) make git-crypt/add/file FILE=.tofu.tfstate
	$(MAKE) make git-crypt/add/file FILE=.tofu.tfstate.backup

gh/repo/organizations/sync: gh/check/deps ## Sync current organizations (owners) with opentofu dir template
	@##~ GITHUB_REPOS_MODULE_DIR=PATH - path to makefile-inc/github-repos dir inside repo.
	@##~                                Optional. If not passed try to resolve in order:
	@##~                                - makefile-github-repos dir directly
	@##~                                - extract path from $(CURDIR)/.gitmodules by makefile-inc/github-repos.git substring
	@${_GH_SYNC_ORGS_INCLUDES} \
	orgs_dirs=(); \
	while IFS= read -r -d '' org_dir; do \
		echo_info "Found org dir '$$org_dir'"; \
		orgs_dirs+=("$$org_dir"); \
	done < <($(FIND_BIN) "$(_GH_ORGANIZATIONS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
	if [ "$${#orgs_dirs[@]}" -eq 0 ]; then \
		echo_warn "Nothing to sync"; \
		exit 0; \
	fi; \
	module_dir=""; \
	if ! module_dir="$$(try_extract_module_dir "$$GITHUB_REPOS_MODULE_DIR")"; then \
		exit_with_err "Cannot resolve or incorrect makefile-inc/github-repos submodule dir. Try to pass with GITHUB_REPOS_MODULE_DIR"; \
	fi; \
	need_commit=""; \
	for org_dir_sync in "$${orgs_dirs[@]}"; do \
		sync_org_with_templates "$$org_dir_sync" "$$module_dir"; \
		if git add "$$org_dir_sync"; then \
			need_commit="true"; \
		fi; \
	done; \
	if [ -n "$$need_commit" ]; then \
		if ! git commit -m "Sync organization with templates"; then \
			echo_warn "Cannot commit synced organizations to git"; \
		fi; \
	fi; \
	echo_info "Organizations synced with templates!"; \
	exit 0

gh/repo/upgrade: gh/bins/install gh/bins/check/required gh/bins/upgrade gh/repo/organizations/sync ## Upgrade deps and sync organizations template and upgrade .gitignore github-repos module
	@##~ GITHUB_REPOS_MODULE_DIR=PATH - path to makefile-inc/github-repos dir inside repo.
	@##~                                Optional. If not passed try to resolve in order:
	@##~                                - makefile-github-repos dir directly
	@##~                                - extract path from $(CURDIR)/.gitmodules by makefile-inc/github-repos.git substring
	@${INCLUDE_ECHO} \
	if ! cp "$(_REPOS_ROOT_DIR)/.gitignore" "$(CURDIR)/.gitignore"; then \
		exit_with_err "Cannot copy .gitignore from makefile-inc/github-repos '$(_REPOS_ROOT_DIR)/.gitignore' to cur infra '$(CURDIR)/.gitignore'"; \
	fi

gh/repo/unlock: gh/bins/install gh/bins/check/required ## Unlock infra repository with git-crypt locally
	@##~ KEY_PATH=PATH - path to key file to unlock
	@$(MAKE) git-crypt/repo/symmetric/unlock

gh/repo/lock: gh/bins/install gh/bins/check/required ## Lock infra repository locally
	@$(MAKE) git-crypt/repo/lock

gh/repo/unlock/after-clone: ## Unlock infra repository fully after clone
	@##~ KEY_PATH=PATH - path to key file to unlock
	@${INCLUDE_ECHO} \
	if [ -z "$$KEY_PATH" ]; then \
		exit_with_err "git-crypt key file is not provided with KEY_PATH param (env)"; \
	fi; \
	user_name="$(USER)"; \
	if [ -z "$$user_name" ]; then \
		exit_with_err "User name is empty in USER env"; \
	fi; \
	echo_info "Chown to '$$user_name:$$user_name' git-crypt key file '$$KEY_PATH' with sudo"; \
	if ! sudo chown "$$user_name:$$user_name" $$KEY_PATH; then \
		exit_with_err "Cannot chown git-crypt key file '$$KEY_PATH'"; \
	fi; \
	key_file=""; \
	if ! key_file="$$(realpath "$$KEY_PATH")"; then \
		exit_with_err "Cannot get real path for '$$KEY_PATH'"; \
	fi; \
	if [ ! -f "$$key_file" ]; then \
		exit_with_err "git-crypt key file '$$key_file' is not file"; \
	fi; \
	echo_info "Install deps from mirror"; \
	if ! $(MAKE) gh/repo/upgrade; then \
		exit_with_err "Cannot install deps from mirror with '$(MAKE) gh/repo/upgrade'"; \
	fi; \
	echo_info "Unlock repo with git-crypt key '$$key_file'"; \
	if ! $(MAKE) gh/repo/unlock KEY_PATH="$$key_file"; then \
		exit_with_err "Cannot unlock repo with '$(MAKE) gh/repo/unlock KEY_PATH=$$key_file'"; \
	fi; \
	if ! $(MAKE) git-crypt/repo/symmetric/check/unlocked; then \
		exit_with_err "Repo is not unlocked"; \
	fi; \
	remove_key_file=""; \
	read -p "Remove key file '$$key_file' [y/n]: " remove_key_file; \
	if [[ "$$remove_key_file" == "y" ]]; then \
		echo_warn "Remove file $$key_file"; \
		if ! rm "$$key_file"; then \
			echo_err "Key file '$$key_file' is not removed!"; \
		fi; \
		exit 0; \
	fi; \
	echo_warn "Removing key file '$$key_file' skipped"

##@ Github repos. Infra. Organizations

organizations:
	@mkdir -p "$(_GH_ORGANIZATIONS_DIR)"

gh/check/deps: gh/bins/check/required git-crypt/repo/symmetric/check/unlocked organizations

gh/infra/organizations/add: gh/check/deps ## Prepare new organization (owner) opentofu dir from template
	@##~ ORG_NAME=NAME    - New organization (owner) name
	@##~ WITH_IMPORT=true - if passed copy needed files to import repositories to new organization dir.
	@##~                    Optional for new organization without need import exists repos
	@##~ GITHUB_REPOS_MODULE_DIR=PATH - path to makefile-inc/github-repos dir inside repo.
	@##~                                Optional. If not passed try to resolve in order:
	@##~                                - makefile-github-repos dir directly
	@##~                                - extract path from $(CURDIR)/.gitmodules by makefile-inc/github-repos.git substring
	@${_GH_SYNC_ORGS_INCLUDES} \
	if [ -z "$$ORG_NAME" ]; then \
		exit_with_err "Org name not passed with 'ORG_NAME' param (env)"; \
	fi; \
	module_dir=""; \
	if ! module_dir="$$(try_extract_module_dir "$$GITHUB_REPOS_MODULE_DIR")"; then \
		exit_with_err "Cannot resolve or incorrect makefile-inc/github-repos submodule dir. Try to pass with GITHUB_REPOS_MODULE_DIR"; \
	fi; \
	org_dir="$(_GH_ORGANIZATIONS_DIR)/$$ORG_NAME"; \
	if ! mkdir -p "$$org_dir"; then \
		exit_with_err "Cannot create owner dir '$$org_dir'"; \
	fi; \
	if sync_org_with_templates "$$org_dir" "$$module_dir"; then \
		echo_info "Org '$$ORG_NAME' prepared. Nothing to commit"; \
		exit 0; \
	fi; \
	if git add "$$org_dir"; then \
		if ! git commit -m "Add/prepare org '$$ORG_NAME'"; then \
			echo_warn "Cannot commit new org '$$ORG_NAME' to git"; \
		fi; \
	fi; \
	if [ -n "$$WITH_IMPORT" ]; then \
		import_src="$(_REPOS_ROOT_DIR)./import"; \
		echo_info "Copy files from '$$import_src' to import exist repositories to '$$org_dir'"; \
		if ! cp -v "$${import_src}/"* "$$org_dir"; then \
			exit_with_err "Cannot copy imports files with 'cp -v $${import_src}/* $$org_dir'"; \
		fi; \
	fi; \
	echo_info "Org '$$ORG_NAME' prepared and commit to git!"; \
	exit 0; \

##@ Github repos. Infra. Sync

gh/infra/sync: export WORKING_DIR = $(CURDIR)
gh/infra/sync: gh/check/deps ## Sync repos with github
	@##~ TOKENS_FILE=PATH  - Path to github tokens file. See $(CURDIR)/sync.sh -h for more info
	@##~                     By default, use $(CURDIR)/.tokens.env
	@##~ ORG_TO_SYNC=NAME  - if passed will sync only passed organization
	@##~ REPO_TO_SYNC=NAME - if passed will sync only passed repo in organization ORG_TO_SYNC
	@##~                     ORG_TO_SYNC should be passed with REPO_TO_SYNC
	@##~ SYNC_ONLY=ORG[/REPO] - if passed will sync only passed repo in organization
	@##~                        or will sync all repos passed in organization
	@##~ SHOW_SENSITIVE=true  - if passed tofu plan will output sensitives.
	@##~                        Useful for import exists repositories
	@if [ -z "$$TOKENS_FILE" ]; then \
		export TOKENS_FILE="$(CURDIR)/.tokens.env"; \
	fi; \
	if ! $(_REPOS_ROOT_DIR)/sync.sh; then \
		exit 1; \
	fi; \

.PHONY: gh/bins/archive gh/bins/install gh/bins/upgrade gh/bins/check/archive/deps gh/check/deps gh/bins/check/required gh/repo/unlock gh/infra/sync gh/infra/organizations/add gh/repo/new/init gh/repo/organizations/sync