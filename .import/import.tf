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
