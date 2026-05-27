terraform {

  required_providers {

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.4.0"
    }

    null = {
      source = "hashicorp/null"
    }

    local = {
      source = "hashicorp/local"
    }

    random = {
      source = "hashicorp/random"
    }

  }
}
