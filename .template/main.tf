terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0" # provider version
    }
  }

  backend "local" {
    path = ".tofu.tfstate"
  }
}

provider "github" {
  owner = "%%OWNER_NAME%%"
}

module "repos" {
  source   = "../../%%MODULE_DIR%%modules/repo"
  
  for_each = { 
    for name, r in local.repos : name => merge(
      r, 
      {"name" = name},
      {"secrets" = lookup(local.secrets, name, {})}
    )
  }

  settings       = each.value
  have_paid_plan = local.have_paid_plan
}