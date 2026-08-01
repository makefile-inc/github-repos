# github-repos

Manage Github repositories via opentofu (terraform)

## Prepare

- Install deps for `makefile-inc/git-crypt`

### Init new repository

Run:

```bash
make repo/new/init KEY_PATH=../PATH_TO_SAVE_GIT_CRYPT_KEY
```

After run, save key file `PATH_TO_SAVE_GIT_CRYPT_KEY` in secret store to unlock repo after clone or lock.

### Clone exists

#### Clone with submodules

```bash
git clone --recurse-submodules git@github.com:name212/repos.git github-repos && cd github-repos
```

#### Unlock repo

- Save `git-crypt` key to file, for example `~/src/github-repos.key`
- if need chmod 

  ``` bash
  sudo chmod "${USER}:${USER}"
  ```

- Run commands:
  ```bash
  make bins/install
  make repo/unlock KEY_PATH=~/src/github-repos.key
  make git-crypt/repo/symmetric/check/unlocked
  ```

- Remove key
  ```bash
  rm -f ~/src/github-repos.key
  ```

### Generate token

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
  - `Metadata`  (read/write)
  - `Secrets`           (read/write)
  - `Variables`         (read/write)
- Save token to file, for example `~/store/gh_token_org_name`

### Add tokens file

Because github allow only one token for one organization you should prepare tokens file.

By default `make sync` uses `./.tokens.env` file for tokens (this file add in git ignore).

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

## Add organizations and repos

### Add organization (owner)

For each github organization you need to prepare your own directory.

[sync script](./sync.sh) runs opentofu for each organization in 
[organizations](./organizations/) directory (organization name is name of dir in `./organizations/` dir)

Before sync you need to add organization you can organization. Repo contains opentofu root module dir template
in [template](./.template/) directory.

For add organization run:

```bash
make github/organizations/add ORG_NAME=YOUR_ORGANIZATION_OR_GITHUB_USER
```

`YOUR_ORGANIZATION_OR_GITHUB_USER` can be organization name or name of Github user.

Target:
- creates `./organizations/ORG_NAME` directory
- Copy all `*.tf` files form [template directory](./.template/) to `./organizations/ORG_NAME` directory
  replaces:
  - `%%OWNER_NAME%%` - to `$ORG_NAME` in all files
- add dir to git and commit.

### Add repos

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
**This file should not change manually!**. For sync with new version use target `make github/organizations/sync`
- `repos.tf` - contains local variable `repos` - map `repo-name` => object of repo settings. 
  All settings described [here](./modules/repo/variables.tf) for `settings` variable.
  **WARNINGS!**:
  - **`name` setting always replaced from map key**
  - **DO NOT SAVE `secrets` setting in `repos.tf`, use `repos.secrets.tf`!**
- `repos.secrets.tf` - contains local variable `secrets` - map `repo-name` => `map(secret_key => secret_variable)`.
  If you want add secrets for repo add key with map. If `secrets` does not contains `repo-name` key,
  secrets will not added or **REMOVED** from repo.
  You can save secrets in file safe, because all `*.secrets.tf` added in `git-crypt` with `make repo/new/init`.
- `paid_plan.tf` - contains local variable `have_paid_plan` (bool).
   Github does not allow some features for private repos in free-plans.
   Module will not create this features, like rulesets for free-plan organizations.
   If you have paid-plan for organization - change to `true` `have_paid_plan` var.

### import repos

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
- [add organization to repo](#add-organization-owner)
  ```bash
  make github/organizations/add ORG_NAME=github-user
  ```
- if you have paid github plan for organization, change `local.have_paid_plan` to `true` in `./organizations/github-user/paid_plan.tf`
- add next files with contents:
  - `./organizations/github-user/repos.tf` (all repos to import **should be** added to `local._import_repos` in `import_repos_list.tf`):
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
  - `./organizations/github-user/import_repos_list.tf` (all repos in `local._import_repos` **should be** add in `repos.tf`!) :
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
  - `./organizations/github-user/import.tf` (**THIS FILE SHOULD NOT BE CHANGED!**):
    ```hcl
    locals {
        # consume import repos with variables
        _repos_with_vars = [ 
            for name, r in local.repos: name 
                if contains(local._import_repos, name) && contains(keys(r), "variables") && length(r.variables) > 0 
        ]

        # create lists for each repo with values "repo_name:variable_name" (it is key for import)
        _var_repos_list = [ 
            for repo_name in local._repos_with_vars: [ 
                for var_name, var_val in local.repos[repo_name].variables: "${repo_name}:${var_name}" 
            ] 
        ]
        
        # all variables for all repos in one list in format "repo_name:variable_name"
        # for using in import for_each
        _vars_list = flatten(local._var_repos_list)

        # consume import repos with secrets
        _repos_with_secrets = [ 
            for name, s in local.secrets: name 
                if contains(local._import_repos, name) && length(s) > 0 
        ]

        # create lists for each repo with values "repo_name:secret_name" (it is key for import)
        _secrets_repos_list = [ 
            for repo_name in local._repos_with_secrets: [
                for secret_name, secret_val in local.secrets[repo_name]: "${repo_name}:${secret_name}" 
            ] 
        ]

        # all secrets for all repos in one list in format "repo_name:secret_name"
        # for using in import for_each
        _secrets_list = flatten(local._secrets_repos_list)

        # consume import repos with enabled actions debug
        # we need only repos here because variable name is constant for enable debug
        # and we construct import id from repo name and constant
        _actions_debug_repos = [ for name, r in local.repos: name if contains(local._import_repos, name) && r.enable_debug_actions ] 
    }

    # import repositories
    import {
        to = module.repos[each.key].github_repository.repo
        id = each.key

        for_each = {
            for r in local._import_repos: r => r
        }
    }

    # Import variables
    import {
        # each.key has format "repo_name:variable_name", see _vars_list
        # github_actions_variable.from_user resource constrict with for_each, name of resource is name of variable
        to = module.repos[split(":", each.key)[0]].github_actions_variable.from_user[split(":", each.key)[1]]
        id = each.key

        for_each = {
            for v in local._vars_list: v => v
        }
    }

    # Import actions debug var
    import {
        # 0 index because github_actions_variable.actions_debug resource is conditional
        # depends on repo.settings.enable_debug_actions
        to = module.repos[each.key].github_actions_variable.actions_debug[0]
        # id for variables "repo_name:variable_name"
        # actions debug enable manage with variable ACTIONS_STEP_DEBUG
        id = "${each.key}:ACTIONS_STEP_DEBUG"

        for_each = {
            for r in local._actions_debug_repos: r => r
        }
    }

    # Import secrets
    import {
        # each.key has format "repo_name:secret_name", see _secrets_list
        # github_actions_secret.from_user resource constrict with for_each, name of resource is name of secret
        to = module.repos[split(":", each.key)[0]].github_actions_secret.from_user[split(":", each.key)[1]]
        id = each.key

        for_each = {
            for s in local._secrets_list: s => s
        }
    }
    ```
- In current import realization you can import `repos` `variables` (with `enable_debug_actions` setting) and `secrets`.
  **Rulesets created by hand does not support!**
  We can add another settings, like `immutable_tags` and `keep_branches` or change description safe,
  but we recommend change another settings or change values and secrets after import.
- **WARNING** All secrets and variables in variable **should be added**, to prevent lost them in tofu state! 
- After add files above run:
  ```bash
  make sync SHOW_SENSITIVE=true
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
  make sync
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

### Remove repos

If you delete repo from map it will remove from state.
All third-party resources will be deleted, but repo will *archived*, not removed.
For remove use Github site for permanently removed repo.
It needs for prevent unnecessary destroy repo!

## Sync

Sync runs `opentofu` for each organization in [organizations](./organizations/) directory
with local state backend.

Sync produce next files and dirs in org dir:
- `.terraform.lock.hcl` - tofu providers lock. Should commit to git.
- `.terraform` - opentofu working dir. Should not committed to git. Excluded in `.gitignore`
- `.tofu.tfstate` - tofu state. Should commit to git. Can safe commit, because all `.tofu.tfstate` added in `git-crypt` with `make repo/new/init`.
- `.tofu.tfstate.backup` - tofu state. Should commit to git. Can safe commit, because all `.tofu.tfstate.backup` added in `git-crypt` with `make repo/new/init`.

### With default tokens files

See [Add tokens file](#add-tokens-file) section for prepare tokens file.

```bash
make sync
```

### Sync one organization (owner)

```bash
make sync ORG_TO_SYNC=organization-name
```

### Sync one repo in organization

```bash
make sync ORG_TO_SYNC=organization-name REPO_TO_SYNC=repo-name
```
