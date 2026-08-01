# Copyright 2026
# license that can be found in the LICENSE file.

variable "settings" {
  type = object({
    # repo name
    name        = string 
    # mark repo as public or private               
    is_public   = optional(bool, true)
    # repo description
    description = string
    # list of topics                
    topics      = optional(set(string))
    # gitignore template (for get: gh repo gitignore list)
    gitignore   = optional(string)
    # license for repo (for get: gh repo license list)
    license     = optional(string, "unlicense") 
    # Set ACTIONS_STEP_DEBUG variable to 'true'
    enable_debug_actions = optional(bool, false)
    # Variables to add to repository
    variables            = optional(map(string), {})
    # Secrets to add to repository
    # If use in makefile-inc/gitub-repos please not pass directly
    # Use ./organizations/ORG/repos.secrets.tf => local.secrets var
    secrets              = optional(map(string), {})

    # additional tags patters that restricted update and delete
    # by default all v.* tags restricted
    # pattern docs:
    #   https://ruby-doc.org/core-2.5.1/File.html#method-c-fnmatch
    #   https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#using-fnmatch-syntax
    immutable_tags = optional(set(string), [])

    # additional branch patterns that restricted no fast forward and delete
    # by default, default branch restricted
    # pattern docs:
    #   https://ruby-doc.org/core-2.5.1/File.html#method-c-fnmatch
    #   https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#using-fnmatch-syntax
    keep_branches = optional(set(string), [])
  })

  description = "Settings objects to repo"
}

variable "have_paid_plan" {
  type        = bool
  description = "Apply paid features (like rulesets) for private repos"
  default     = false
}
