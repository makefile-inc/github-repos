# Copyright 2026
# license that can be found in the LICENSE file.

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
    }
  }
}

resource "github_repository" "repo" {
  name        = var.settings.name
  visibility  = var.settings.is_public ? "public" : "private"
  auto_init   = true
  is_template = false

  allow_forking      = var.settings.is_public ? true : null
  archive_on_destroy = true

  description = var.settings.description
  topics      = var.settings.topics

  license_template   = var.settings.license
  gitignore_template = var.settings.gitignore

  has_issues      = true
  has_discussions = false
  has_projects    = false
  has_wiki        = false

  allow_auto_merge       = false
  allow_merge_commit     = false
  delete_branch_on_merge = true

  allow_rebase_merge          = true
  allow_squash_merge          = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"

  web_commit_signoff_required = true

  security_and_analysis {
    # dynamic "advanced_security" {
    #   for_each = var.settings.is_public ? [] : ["disabled"]
    #   content {
    #     status = advanced_security.value
    #   }
    # }

    dynamic "code_security" {
      for_each = var.settings.is_public ? [] : ["disabled"]
      content {
        status = code_security.value
      }
    }

    secret_scanning {
      status = var.settings.is_public ? "enabled" : "disabled"
    }

    secret_scanning_push_protection {
      status = var.settings.is_public ? "enabled" : "disabled"
    }

    dynamic "secret_scanning_ai_detection" {
      for_each = var.settings.is_public ? [] : ["disabled"]
      content {
        status = secret_scanning_ai_detection.value
      }
    }

    dynamic "secret_scanning_non_provider_patterns" {
      for_each = var.settings.is_public ? [] : ["disabled"]
      content {
        status = secret_scanning_non_provider_patterns.value
      }
    }
  }
}

resource "github_repository_ruleset" "keep_default_branch" {
  count = (var.have_paid_plan || var.settings.is_public) ? 1 : 0

  name        = "keep_default_branch"
  repository  = github_repository.repo.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true
  }
}

resource "github_repository_ruleset" "keep_branches" {
  count = (var.have_paid_plan || var.settings.is_public) && length(var.settings.keep_branches) > 0 ? 1 : 0

  name        = "keep_branches"
  repository  = github_repository.repo.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = [for b in tolist(var.settings.keep_branches) : "refs/heads/${b}"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true
  }
}

resource "github_repository_ruleset" "immutable_v_tags" {
  count = (var.have_paid_plan || var.settings.is_public) ? 1 : 0

  name        = "immutable_v_tags"
  repository  = github_repository.repo.name
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  rules {
    deletion = true
    update   = true
  }
}

resource "github_repository_ruleset" "immutable_tags" {
  count = (var.have_paid_plan || var.settings.is_public) && length(var.settings.immutable_tags) > 0 ? 1 : 0

  name        = "immutable_tags"
  repository  = github_repository.repo.name
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = [for t in tolist(var.settings.immutable_tags) : "refs/tags/${t}"]
      exclude = []
    }
  }

  rules {
    deletion = true
    update   = true
  }
}

# Push protection
# NOT AVAILABLE NOW. See https://github.com/orgs/community/discussions/184348
# locals {
#   const_push_maintainers = "~MAINTAINERS"
#   const_push_maintainers_id = 2

#   push_protect = contains(keys(var.settings), "push_protect") ? var.settings.push_protect : {} 
#   push_protect_wf = local.push_protect != null && contains(keys(local.push_protect), "workflows") ? local.push_protect.workflows : tolist([])
#   push_protect_all = local.push_protect != null && contains(keys(local.push_protect), "all") ? local.push_protect.all : tolist([])
  
#   push_protect_wf_has_maintainers = contains(local.push_protect_wf, local.const_push_maintainers)
#   push_protect_all_has_maintainers = contains(local.push_protect_all, local.const_push_maintainers)

#   push_protect_wf_users = toset([ for u in local.push_protect_wf: u if u != local.const_push_maintainers ])
#   push_protect_all_users = toset([ for u in local.push_protect_all: u if u != local.const_push_maintainers ])
# }

# data "github_user" "push_protect_wf" {
#   for_each = local.push_protect_wf_users
#   username = each.key
# }

# data "github_user" "push_protect_all" {
#   for_each = local.push_protect_all_users
#   username = each.key
# }

# resource "github_repository_ruleset" "restrict_push_workflows" {
#   count = (var.have_paid_plan || var.settings.is_public) && (length(local.push_protect_wf) > 0 && length(local.push_protect_all) == 0) ? 1 : 0

#   name        = "restrict_push_workflows"
#   repository  = github_repository.repo.name
#   target      = "push"
#   enforcement = "active"

#   rules {
#     file_path_restriction {
#       restricted_file_paths = [".github/workflows/*"]
#     }
#   }

#   dynamic "bypass_actors" {
#     for_each = concat(
#       local.push_protect_wf_has_maintainers ? [{
#         id = local.const_push_maintainers_id
#         tp = "RepositoryRole"
#       }] : [],

#       length(local.push_protect_wf_users) > 0 ? [
#         for u in data.github_user.push_protect_wf: {
#           id = u.id
#           tp = "User"
#         }] : []
#     )

#     content {
#       bypass_mode = "always"
#       actor_id = bypass_actors.value.id
#       actor_type = bypass_actors.value.tp
#     }
#   }
# }

# resource "github_repository_ruleset" "restrict_push_all" {
#   count = (var.have_paid_plan || var.settings.is_public) && length(local.push_protect_all) > 0 ? 1 : 0

#   name        = "restrict_push_all"
#   repository  = github_repository.repo.name
#   target      = "push"
#   enforcement = "active"

#   rules {
#     file_path_restriction {
#       restricted_file_paths = ["*"]
#     }
#   }

#   dynamic "bypass_actors" {
#     for_each = concat(
#       local.push_protect_all_has_maintainers ? [{
#         id = local.const_push_maintainers_id
#         tp = "RepositoryRole"
#       }] : [],

#       length(local.push_protect_all_users) > 0 ? [
#         for u in data.github_user.push_protect_all: {
#           id = u.id
#           tp = "User"
#         }] : []
#     )

#     content {
#       bypass_mode = "always"
#       actor_id = bypass_actors.value.id
#       actor_type = bypass_actors.value.tp
#     }
#   }
# }

resource "github_actions_variable" "actions_debug" {
  count = var.settings.enable_debug_actions ? 1 : 0

  repository    = github_repository.repo.name
  variable_name = "ACTIONS_STEP_DEBUG"
  value         = "true"
}

resource "github_actions_variable" "from_user" {
  for_each = var.settings.variables

  repository    = github_repository.repo.name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_secret" "from_user" {
  for_each = var.settings.secrets

  repository  = github_repository.repo.name
  secret_name = each.key
  value       = each.value
}
