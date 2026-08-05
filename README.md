# github-repos

Manage Github repositories via opentofu (terraform).

Support `linux/amd64` platform now.

## Dependencies

Uses https://github.com/makefile-inc/git-crypt

Please [see](https://github.com/makefile-inc/git-crypt#dependencies) for install deps.

## Install

Because this repo uses in final repo for infrastructure, `include.mk.inc` file
include all submodules from this repo.

### Manual

You can copy all files in your own repo (for example in subdir `makefile-github-repos`) 
and include in root Makefile in the next way:

```Makefile
include $(CURDIR)/makefile-github-repos/include.mk.inc
```

### As submodule

Add submodule:

```bash
git submodule add git@github.com:makefile-inc/github-repos.git makefile-github-repos
```

Checkout to target version:

```bash
pushd .
cd makefile-github-repos
git fetch -a && git checkout v0.3.0
git submodule update --recursive --init 
popd
```

Include in root Makefile in the next way:

```Makefile
include $(CURDIR)/makefile-github-repos/include.mk.inc
```

**WARNING! If you use submodule and github actions, add to checkout action checkout submodules `submodules: "recursive"`, like:**
```yaml
...
    steps:
      - &checkout_step
        name: Checkout
        uses: actions/checkout@v6.0.2
        with:
          fetch-depth: 0
          submodules: "recursive"
          ref: ${{ github.event.pull_request.head.sha }}
...
```

## Update as submodule

```bash
pushd .
cd makefile-github-repos
git fetch -a && git checkout NEW_TAG
git submodule update --recursive
popd
```

## Post install/update

Please add to `.gitignore` all entries from this repository `.gitignore`.

and run `make common/git/check/gitignore GITIGNORES_WITH_REQUIRED_RULES=makefile-github-repos/.gitignore`.

Because targets generate some files which do not commit to git repo.

You **should** run:

```bash
make gh/repo/upgrade
```

to:
- upgrade bins deps from [mirror dir](./.mirror)
- sync root tofu module [template dir](./.template)
- update `.gitignore` from this repo to your repo.

**WARNING!** If you install submodule not to directory `makefile-github-repos` or not with submodule, pass
`GITHUB_REPOS_MODULE_DIR` params to upgrade target, for example module installed in `makefiles/github-repos` dir:

```bash
make gh/repo/upgrade GITHUB_REPOS_MODULE_DIR="makefiles/github-repos"
```

Sync root tofu module only force resync `main.tf` and add not present files.

**But, before sync repos please check that another files not changed to prevent unnecessary destroy/change repositories!**

## Description

### Deps includes in repo

This repo contains archive with all needed binaries to work.
This needs for local runs without download tofu plugins, tofu and git-crypt (for save secrets and states security in you repo). This will allow reproduce sync in all depends repos.
All binaries compress to `xz` archive (tofu binary has big length and we avoid use git-lfs for save binaries).
Also for all binaries we calculate `sha256sum` and verify sums after unarchive.
Archives and checksums file saved in [.mirror](./.mirror) dir in format:
- `bins_$(OS_CALCULATED)_$(ARCH_CALCULATED).tar.xz` - archive with binaries for platform
- `bins_$(OS_CALCULATED)_$(ARCH_CALCULATED).sha256sum` - sum-file for binaries for platform

Archive contains next binaries:
- `tofu` - [opentofu](https://github.com/opentofu/opentofu) binary with version `v1.12.5`
- `registry.opentofu.org/integrations/github/6.13.0/PLATFORM/terraform-provider-github` - [github tofu provider](https://github.com/integrations/terraform-provider-github) binary with version `6.13.0`
- `git-crypt` - static build of [git-crypt](https://github.com/AGWA/git-crypt) with version `0.8.0`

During install binaries will unarchive to `$(CURDIR)/bin` directory.

Binaries will install with next targets:
- `gh/bins/install`
- `gh/bins/upgrade`
- `gh/repo/upgrade`
- and with init repo target `gh/repo/new/init`

### Opentofu (terraform) module

This repo provides tofu(terraform) module placed [here](./modules/repo/)

This module:
- creates github repo
- protect default branch from `force push` and `deletion` 
- protect all `v*` tags from `update` and `deletion` 
- add variables and secrets for repo
- enable `github actions` debug
- protect additional branches and tags with same rules for default branch and `v*` tags.

Repo will create (change during import) with next unchangeable settings:
- `archive when destroy` - see [remove repos](#remove-repos) section
- `issues` enabled
- `discussions`, `projects`, `wiki` disabled
- `sign-off` enabled for public repos
- `delete branches on merge` enabled
- pull request merge settings:
  - `merge commit` disabled
  - `squash` and `rebase` enabled.
    This needs for get linear history on default branch
  - `commit title` is pull request title.
    For prevent incorrect commit message like `++`
  - `commit message` is pull request title.
    - Pull request description should contains goals, all changes, fixes and motivations 
      for perfect pr description. User can see all motivations in changes.
    - Also, because you can migrate from github to another solutions, your
      commit history should contains all motivations for every commit.
    - Git should source of true for all description and motivations about every change,
      because all solutions can stale, git is immortal 😊.
    - Also, if you will use `git blame`, you will see change motivation straightaway
      in your tools. 
- next security setting will disable for private repos, because these settings only available
  in paid-plans and can break destroy repo. Also, you can use third-party solutions for them:
  - `code security`
  - `secret scanning`
  - `secret scanning push protection`
- next security setting will disable for all repos
  - `secret_scanning_ai_detection` (tokens economy)
  - `secret_scanning_non_provider_patterns` (see motivation below for security settings)

#### Opentofu (terraform) module. Variables

Module take next variables:
- `settings` - object with repo settings. Have next [attributes](./modules/repo/variables.tf):
  - `name` **(`string`, Required)** - repo name
  - `is_public` **(`bool`, Optional, default - `true`)** - repo visibility. If `true` - public, otherwise - private.
  - `description` **(`string`, Required)* - repo description
  - `topics` **(`set(string)`, Optional, default - `{}`)** - list of topics
  - `gitignore` **(`string`, Optional, default - `null`)** - gitignore template. 
    For get available values run `gh repo gitignore list`
  - `license` **(`string`, Optional, default - `"unlicense"`)** - license for repo.
    For get available values run `gh repo license list`
  - `enable_debug_actions` **(`bool`, Optional, default - `false`)** - enable debug for `github actions` (set `ACTIONS_STEP_DEBUG` variable to `true`)
  - `variables` **(`map(string)`, Optional, default - `{}`)** - set variables for repo
  - `secrets` **(`map(string)`, Optional, default - `{}`)** - set secrets for repo.
    If use in `makefile-inc/gitub-repos` please **not pass** directly!
    Use `./organizations/ORG/repos.secrets.tf` => `local.secrets` (this file will encrypted with `git-crypt`)
  - `immutable_tags` **(`set(string)`, Optional, default - `[]`)** - additional tags patters that restricted update and delete.
    By default all `v.*` tags restricted.
    Pattern docs:
       - https://ruby-doc.org/core-2.5.1/File.html#method-c-fnmatch
       - https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#using-fnmatch-syntax
  - `keep_branches` **(`set(string)`, Optional, default - `[]`)** - additional branches patterns that 
    restricted `no fast forward` and `delete`.
    By default, default branch restricted.
    Pattern docs:
       - https://ruby-doc.org/core-2.5.1/File.html#method-c-fnmatch
       - https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#using-fnmatch-syntax
- `have_paid_plan` **(`bool`, Optional, default - `false`)** - Apply paid features (like rulesets) for private repos.

We are using settings as standalone object, not separated variables for using maps of repositories
and simple usage in organizations root modules.

#### Opentofu (terraform) module. Usage

See [main.tf](./.template/main.tf) for example.

### Makefile repo

This repo contains [sync.sh](./sync.sh) script for synchronize repos with github
and some `make` targets for init/upgrade, synchronize repos and some utils for prepare your repo.

This repo contains `.gitignore` file for exclude tofu working files from your repo.

Sync runs `tofu` with local backend without lock. This allow save state in same repo.

Because state files (own for each organization) and also secrets variables for repos 
contains sensitive information, we need encrypt them. For this, we are using
[git-crypt](https://github.com/AGWA/git-crypt). After your repo initialization with 
`gh/repo/new/init` or upgrade with `gh/repo/upgrade`, next files will add to encrypt:
- `*.secrets.tf` - files with secrets
- all `.tofu.tfstate` - current tofu state
- all `.tofu.tfstate.backup` - previous (backup) tofu state.

Sync produce next files and dirs in org dir:
- `.terraform.lock.hcl` - tofu providers lock. Should commit to git.
- `.terraform` - opentofu working dir. Should not committed to git. Excluded in `.gitignore`
- `.tofu.tfstate` - tofu state. Should commit to git. Can safe commit, because all `.tofu.tfstate` added in `git-crypt` with `make gh/repo/new/init`.
- `.tofu.tfstate.backup` - tofu state. Should commit to git. Can safe commit, because all `.tofu.tfstate.backup` added in `git-crypt` with `make gh/repo/new/init`.

#### Add organizations and repos to your repo

##### Add organization (owner)

For each github organization you need to prepare your own directory.

[sync script](./sync.sh) runs opentofu for each organization in 
[organizations](./organizations/) directory (organization name is name of dir in `./organizations/` dir)

Before sync you need to add organization you can organization. Repo contains opentofu root module dir template
in [template](./.template/) directory.

For add organization run:

```bash
make gh/infra/organizations/add ORG_NAME=YOUR_ORGANIZATION_OR_GITHUB_USER
```

`YOUR_ORGANIZATION_OR_GITHUB_USER` can be organization name or name of github user.

**WARNING!** If you install submodule not to directory `makefile-github-repos` or not with submodule, pass
`GITHUB_REPOS_MODULE_DIR` params to target, for example module installed in `makefiles/github-repos` dir:

```bash
make gh/infra/organizations/add ORG_NAME=YOUR_ORGANIZATION_OR_GITHUB_USER GITHUB_REPOS_MODULE_DIR="makefiles/github-repos"
```

Target:
- creates `./organizations/ORG_NAME` directory
- Copy all `*.tf` files form [template directory](./.template/) to `./organizations/ORG_NAME` directory
  replaces:
  - `%%OWNER_NAME%%` - to `$ORG_NAME` in all files
  - `%%MODULE_DIR%%` - to `makefile-inc/github-repos` dir passed with `GITHUB_REPOS_MODULE_DIR` or automatically resolved with `/` ending
- add dir to git and commit.

##### Add repos

After [add organization](#add-organization-owner) you will get next structure:
```
./organizations/ORG/
├── main.tf
├── paid_plan.tf
├── repos.secrets.tf
├── repos.tf
```
Files description:
- `main.tf` - contains tofu description about provider and run modules described in `repos.tf` and `repos.secrets.tf`.
**This file should not change manually!**. For sync with new version use target `make gh/repo/upgrade`
- `repos.tf` - contains local variable `repos` - map `repo-name` => object of repo settings. 
  All settings described [here](#opentofu-terraform-module-variables) for `settings` variable.
  **WARNINGS!**:
  - **`name` setting always replaced from map key**
  - **DO NOT SAVE `secrets` setting in `repos.tf`, use `repos.secrets.tf`!**
- `repos.secrets.tf` - contains local variable `secrets` - map `repo-name` => `map(secret_key => secret_variable)`.
  If you want add secrets for repo add key with map. If `secrets` does not contains `repo-name` key,
  secrets will not added or **REMOVED** from repo.
  You can save secrets in file safe, because all `*.secrets.tf` added in `git-crypt` with `make gh/repo/new/init`.
- `paid_plan.tf` - contains local variable `have_paid_plan` (bool).
   Github does not allow some features for private repos in free-plans.
   Module will not create this features, like rulesets for free-plan organizations.
   If you have paid-plan for organization - change to `true` `have_paid_plan` var.

#### Prepare your own repo

##### Init new repository

Run:

```bash
make gh/repo/new/init KEY_PATH=../PATH_TO_SAVE_GIT_CRYPT_KEY
```

After run, save key file `PATH_TO_SAVE_GIT_CRYPT_KEY` in secret store to unlock repo after clone or lock.

##### Clone exists with submodules

```bash
git clone --recurse-submodules YOUR_INFRA_REPO github-repos && cd github-repos
```

You can use `gh/repo/unlock/after-clone` target with param `KEY_PATH`. 

**WARNING! We mean that you will use temp git-crypt key file!**

This target will do:
- check `KEY_PATH` passed and not empty
- chown `KEY_PATH` to `$(USER):$(USER)` with `sudo`
- check thar `KEY_PATH` is file
- install deps from local mirror with target `gh/repo/upgrade`
- unlock repo with `git-crypt` with target `gh/repo/unlock` and passed key file
- ask user about remove key file and remove if get accept from user.

For example:
- Save `git-crypt` key to **temp file**, for example `~/src/github-repos.key`
- run

  ``` bash
  make gh/repo/unlock/after-clone KEY_PATH=~/src/github-repos.key
  ```

##### Generate token

For access to github, tofu provider require github token.
In this realization you can use `Personal Access Token (PAT)`.
If you you have multiple organizations, you should create
it own PAT for each organization.

For each organizations:
- Go to https://github.com/settings/personal-access-tokens
- Choice organization
- Set `Repository access` to `All repositories`
- Set next permissions for repositories:
  - `Administration`    (read/write)
  - `Artifact metadata` (read)
  - `Contents`          (read/write)
  - `Custom properties` (read/write)
  - `Environments`      (read/write)
  - `Issues`            (read/write)
  - `Metadata`          (read/write)
  - `Secrets`           (read/write)
  - `Variables`         (read/write)
- Save token to file, for example `~/store/gh_token_org_name`

###### Add tokens file

Because github allow only one token for one organization you should prepare tokens file.

By default `make gh/infra/sync` uses `./.tokens.env` file for tokens (this file add in git ignore).

This file should be in `dot env` format with specific variables format. 
You can prepare this file in next variables formats:
- pass path's to Github token. Variables name should be start with `GITHUB_TOKEN_FILE_` prefix.
  Value is string in format `ORG_NAME||PATH_TO_TOKEN`. For example:
  ```bash
  GITHUB_TOKEN_FILE_my_user="my-user||/home/user/store/gh_token_my_user"
  GITHUB_TOKEN_FILE_my_org="my-org||/home/user/store/gh_token_my_org"
  ```
  If needs, script can try read token with `sudo`.
- pass Github token string directly. Variables name should be start with `GITHUB_TOKEN_STRING_` prefix.
  Value is string in format `ORG_NAME||TOKEN`. For example:
  ```bash
  GITHUB_TOKEN_STRING_my_user="my-user||github_pat_11...."
  GITHUB_TOKEN_STRING_my_org="my-org||github_pat_22....."
  ```
- mix token files and tokens strings:
  ```bash
  GITHUB_TOKEN_FILE_my_user="my-user||/home/user/store/gh_token_my_user"
  GITHUB_TOKEN_STRING_my_org="my-org||github_pat_22....."
  ```


##### Import repos

Maybe, you already have repositories in github and you want to add
these repos for synchronization.

Imagine, we have next two repos in you user account `github-user` with next characteristics: 
- `test-tf-import-public`:
   - Public 
   - Description: `Test terraform repo public`
   - Topics: `"test`, `terraform`
   - License: `mit` (MIT)
   - Variables: 
     - `ACTIONS_STEP_DEBUG` not set (is is `enable_debug_actions = false`)
     - `VAR_IMPORT` = `val`
- `test-tf-import-private`:
   - Private 
   - Description: `Test terraform repo private`
   - Topics: `"test`, `terraform`, `makefile`
   - License: `mit` (MIT)
   - Variables: 
     - `ACTIONS_STEP_DEBUG` is set (is is `enable_debug_actions = true`)
  - Secrets:
    - `SECRET_TO_IMPORT` = `secret`

For import these repositories you need:
- [init repo](#init-new-repository)
- [generate token](#generate-token)
- [prepare tokens file](#add-tokens-file)
- [add organization to repo](#add-organization-owner) with param `WITH_IMPORT=true`:
  ```bash
  make gh/infra/organizations/add ORG_NAME=github-user WITH_IMPORT=true
  ```
- if you have paid github plan for organization, change `local.have_paid_plan` to `true` in `./organizations/github-user/paid_plan.tf`
- add/change next files with contents:
  - `./organizations/github-user/repos.tf` (all repos to import **should be add** to `local._import_repos` in `import_repos_list.tf`):
    ```hcl
    locals {
      repos = {
        "test-tf-import-public" = {
            is_public   = true
            description = "Test terraform repo public"
            topics      = ["test", "terraform"]
            license     = "mit" 

            enable_debug_actions = false
            variables = {
              "VAR_IMPORT" = "val"
            }
        }
        "test-tf-import-private" = {
            is_public   = false
            description = "Test terraform repo private"
            topics      = ["test", "terraform", "makefile"]
            license     = "mit" 

            enable_debug_actions = true
        }
      }
    }
    ```
  - `./organizations/github-user/repos.secrets.tf`:
    ```hcl
    locals {
        secrets = {
            "test-tf-import-private" = { 
                "SECRET_TO_IMPORT" = "secret"
            }
        }
    }
    ```
  - `./organizations/github-user/import_repos_list.tf` (all repos in `local._import_repos` **should be add** in `repos.tf`!) :
    Add repos list to var `local_import_repos` like:
    ```hcl
    locals {
        # list repos for import
        # WARNING! This repos should be present in repos.tf file!
        _import_repos = [
            "test-tf-import-public",
            "test-tf-import-private",
        ]
    }
    ``` 
  - `./organizations/github-user/import.tf` added with run `gh/infra/organizations/add` target with param `WITH_IMPORT=true`.
    **THIS FILE SHOULD NOT BE CHANGED!**
- In current import realization you can import `repos` `variables` (with `enable_debug_actions` setting) and `secrets`.
  **Rulesets created by hand does not support!**
  We can add another settings, like `immutable_tags` and `keep_branches` or change description safe,
  but we recommend change another settings or change values and secrets after import.
- **WARNING** All secrets and variables in variable **should be added**, to prevent lost them in tofu state! 
- After add files above run:
  ```bash
  make gh/infra/sync SHOW_SENSITIVE=true
  ```
- Before approve plan, please check plan. Plan can have `creates` and `updates` (**in-place**).
  ***WARNING** Because github not retrieve secrets values you will get `in-place` update
  for resource `"github_actions_secret" "from_user"` (`create` plan for value), like:  
  ```
  # module.repos["test-tf-import-private"].github_actions_secret.from_user["SECRET_TO_IMPORT"] will be updated in-place
  # (imported from "test-tf-import-private:SECRET_TO_IMPORT")
  ~ resource "github_actions_secret" "from_user" {
          created_at        = "2026-07-31 22:23:23 +0000 UTC"
          id                = "test-tf-import-private:SECRET_TO_IMPORT"
          remote_updated_at = "2026-07-31 22:23:23 +0000 UTC"
          repository        = "test-tf-import-private"
          repository_id     = 1318791032
          secret_name       = "SECRET_TO_IMPORT"
          updated_at        = "2026-07-31 22:23:23 +0000 UTC"
        + value             = "secret"
      }
  ```
- approve tofu plan with input `y`, and wait finish import operation.
- after finish remove files (this files added in `.gitignore` by default and **should not** commit to git!):
  - `./organizations/github-user/import.tf`
  - `./organizations/github-user/import_repos_list.tf`
- and run:
  ```bash
  make gh/infra/sync
  ```
  for check, that plan has not destructive changes.
- Commit all changes in `./organizations/github-user` directory.

Congratulations! You imported repositories!

After import, you can prepare:
- `immutable_tags` and `keep_branches` settings
- because we do not support import and manage custom rulesets, you can remove you own created rulesets
- add/change/remove variables and secrets
- add new repos.

If you have multiple organizations, add them with steps above from `generate token` step.

##### Remove repos

If you delete repo from map it will remove from state.
All third-party resources will be deleted, but repo will *archived*, not removed.
For remove use Github site for permanently removed repo.
It needs for prevent unnecessary destroy repo!

## Targets

### Mirror binaries

- `gh/bins/upgrade` - install binaries from `.mirror` to `$(CURDIR)/bin`

### Your infra repo utils

- `gh/repo/new/init` - init new repository after create with git-crypt.
  
  Params:
  - `KEY_PATH`=*PATH* - path to save git-crypt key. Should be outside the repo (current dir)

- `gh/repo/unlock/after-clone` - unlock infra repository fully after clone.
  See [clone repo](#clone-exists-with-submodules) section for more information.

  Params:
  - `KEY_PATH`=*PATH* - path to save git-crypt key. Should be outside the repo (current dir)

- `gh/repo/upgrade` - upgrade deps and sync organizations template and upgrade `.gitignore` after upgrade `github-repos` module
   
   Params:
   - `GITHUB_REPOS_MODULE_DIR`=*PATH* - path to makefile-inc/github-repos dir inside repo.
	    Optional. If not passed try to resolve in order:
	   - `makefile-github-repos` dir directly
	   - extract path from `$(CURDIR)/.gitmodules` by `makefile-inc/github-repos.git` substring

- `gh/repo/unlock` - unlock infra repository with `git-crypt` locally

- `gh/repo/lock` - lock infra repository locally

### Organizations

- `gh/infra/organizations/add` - prepare (add) new organization (owner) opentofu dir from `./.template`
  
  Params:
  - `ORG_NAME`=*NAME*    - new organization (owner) name
  - `WITH_IMPORT`=*true* - if passed copy needed files to import repositories to new organization dir.
	  Optional for new organization without need import exists repos
  - `GITHUB_REPOS_MODULE_DIR`=*PATH* - path to makefile-inc/github-repos dir inside repo.
	    Optional. If not passed try to resolve in order:
	   - `makefile-github-repos` dir directly
	   - extract path from `$(CURDIR)/.gitmodules` by `makefile-inc/github-repos.git` substring

### Sync

- `gh/infra/sync` - sync repos with github.

  Params:
	- `TOKENS_FILE`=*PATH*  - Path to github tokens file. See `$(CURDIR)/sync.sh -h` for more info.
	  By default, use `$(CURDIR)/.tokens.env`
	- `ORG_TO_SYNC`=*NAME*  - if passed will sync only passed organization
	- `REPO_TO_SYNC`=*NAME* - if passed will sync only passed repo in organization `ORG_TO_SYNC`
	  `ORG_TO_SYNC` should be passed with `REPO_TO_SYNC`
	- `SYNC_ONLY`=*ORG[/REPO]* - if passed will sync only passed repo in organization
	  or will sync all repos passed in organization
	- `SHOW_SENSITIVE`=*true*  - if passed tofu plan will output sensitives.
	  Useful for import exists repositories 

## Examples

### Init new repo

See [init new repo](#init-new-repository) section.

#### Create new repo

```bash
mkdir -p github-infra-repo && cd github-infra-repo
git init
echo "# github infra repo" > README.md
git add README.md
git commit -m "init"
git branch -m main
git submodule add git@github.com:makefile-inc/github-repos.git makefile-github-repos
pushd .
cd makefile-github-repos
git fetch -a && git checkout v0.3.0
git submodule update --recursive --init 
popd
echo 'include $(CURDIR)/makefile-github-repos/include.mk.inc' > Makefile
git add *
git commit -m "Add github repos submodule"
make gh/repo/new/init KEY_PATH=../infra-repos.key
```

#### With already created repo:

```bash
git clone ... github-infra-repo # Your repo
git checkout -b add-github-repos-module
git submodule add git@github.com:makefile-inc/github-repos.git makefile-github-repos
pushd .
cd makefile-github-repos
git fetch -a && git checkout v0.3.0
git submodule update --recursive --init 
popd
echo 'include $(CURDIR)/makefile-github-repos/include.mk.inc' > Makefile
git add *
git commit -m "Add github repos submodule"
make gh/repo/new/init KEY_PATH=../infra-repos.key
git push -u origin add-github-repos-module
```

### Clone exists

See [clone](#clone-exists-with-submodules) section.

### Upgrade you repo after upgrade makefile-inc/github-repos

```bash
make gh/repo/upgrade
```

### Add organizations/repos

See [here](#add-organizations-and-repos-to-your-repo).

### Logical separation your repos in organization

For example, `makefile-inc` contains two kinds of repos:
- repos with includes 
- tests repos for some repos.

For each repos in the group we can have some same default setting and its setting can be rewrite for some repositories.
And for different groups we can have different defaults.

For example, every repositories should have 
- next topics and can add additional topics: 
  - `makefile`
  - `make` 
  - `makefile-snippets` 
  - `includes`

- `MIT` license 

But for tests repos:
- all repos names should start with `tests-`
- unlicensed
- description should be `Tests repository for repo ${REPO_URL}`


For realize it, we can prepare next files structures: 

```
./organizations/makefile-inc
├── repos-includes.tf # for includes repositories
├── repos-tests.tf    # for tests repositories
├── repos.tf          # merge repositories to one map
```

With next contents (see commentaries for descriptions):
- `repos-includes.tf`:
  ```hcl
  locals {
      # repositories lists with own settings for includes repos
      _includes_repos_list = {
          "common" = {
              description = "Common makefiles includes for another repos"
          }

          "openapi" = {
              description = "Makefiles includes for generations client and servers and conversions openapi specs"
              topics      = [
                  "openapi",
              ]
          }

          "go" = {
              description = "Includes for Make files for go operations like lint, test, build"
              topics      = [
                  "golang", 
                  "linting",
                  "testing",
              ]
          }

          "git-crypt" = {
              description = "Makefiles include for using git-crypt https://github.com/AGWA/git-crypt"
              topics      = [
                  "git", 
                  "encryption",
              ],

              keep_branches = [
                  "git-crypt-bin"
              ],
              immutable_tags = [
                  "git-crypt-bin*",
              ],
          }

          "github-repos" = {
              description = "Manage Github repositories via opentofu (terraform)"
              topics      = [
                  "git", 
                  "github",
                  "terraform-module",
                  "terraformed",
                  "iac",
                  "opentofu",
              ]
          }
      }

      # prepare desired repos list to merge in repos.tf
      _includes_repos = {
          # creates new map repo_name => settings to module via merges maps
          for name, setts in local._includes_repos_list: name => merge(
              # default settings map
              {
                  is_public   = true
                  license     = "mit"
                  enable_debug_actions = false
              },

              # override settings from repos list above 
              setts,

              # add required topics and add additional if they contains in repos list above 
              {
                  topics = concat(
                      ["makefile", "make", "makefile-snippets", "includes"],
                      contains(keys(setts), "topics") ? setts.topics : [],
                  )
              },
          )
      }
  }
  ```

- `repos-tests.tf`:
  ```hcl
  locals {
       # repositories lists for tests repos here we set settings different for module
      _tests_repos_list = {
          "git-crypt" = {
              # each repo should contains 'repo_url' setting to set to description
              repo_url = "https://github.com/makefile-inc/git-crypt"
          }

          "go" = {
              repo_url = "https://github.com/makefile-inc/go"
          }

          "github-repos" = {
              repo_url = "https://github.com/makefile-inc/github-repos"
          }
      }

      # prepare desired repos list to merge in repos.tf
      _test_repos = {
          # creates new map repo_name_with_tests_prefix => settings to module via merges maps
          for name, setts in local._tests_repos_list: "tests-${name}" => merge(
              # default settings map
              {
                  is_public   = true
                  license     = "unlicense"
                  enable_debug_actions = true
              },

              # Add desired description with repo url from repos list above
              {
                  description = "Tests repository for repo ${setts.repo_url}"
              },
              
              # if needs rewrite/add settings from repos list above
              # repo with additional settings can contains 'settings' object
              # if not passed, use empty object
              contains(keys(setts), "settings") ? setts.settings : {},
          )
      }
  }
  ```

- `repos-includes.tf`:
  ```hcl
  locals {
      # module requires local.repos variable with list repos to sync
      # merge all desired map from desired local variables for each group
      repos = merge(
          local._includes_repos, 
          local._test_repos,
      )
  }
  ```
### Sync

#### With default tokens files

See [Add tokens file](#add-tokens-file) section for prepare tokens file.

```bash
make gh/infra/sync
```

#### Sync one organization (owner)

```bash
make gh/infra/sync ORG_TO_SYNC=organization-name
```

#### Sync one repo in organization

```bash
make gh/infra/sync ORG_TO_SYNC=organization-name REPO_TO_SYNC=repo-name
```

## Development

### Upgrade binaries

In this repo:
- Copy binaries to `./bin`
- Run:

  ```bash
  make gh/bins/archive
  ```
- if you change version of `terraform-provider-github`, please change version in [main.tf](./.template/main.tf) template file
- Commit.
- Add warning about needs to run `make gh/repo/upgrade`
