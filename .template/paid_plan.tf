locals {
    # Github does not allow some features for private repos
    # in free-plans. Module will not create this features, like
    # rulesets for free-plan organizations
    # if you have paid-plan for organization - pass true to have_paid_plan
    have_paid_plan = false
}
