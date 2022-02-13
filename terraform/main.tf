terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.83.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
  }
  backend "azurerm" {

  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

locals {
  func_name = "funcslot${random_string.unique.result}"
  loc_for_naming = lower(replace(var.location, " ", ""))
  tags = {
    "managed_by" = "terraform"
    "repo"       = "azure-function-deploymentslots"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.func_name}-${local.loc_for_naming}"
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}


data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "default" {
  name                = "DefaultWorkspace-${data.azurerm_client_config.current.subscription_id}-EUS"
  resource_group_name = "DefaultResourceGroup-EUS"
} 

data "azurerm_network_security_group" "basic" {
    name                = "basic"
    resource_group_name = "rg-network-eastus"
}

resource "azurerm_storage_account" "sa" {
  name                     = "sa${local.func_name}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = local.tags
}

resource "azurerm_app_service_plan" "asp" {
  name                = "asp-${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "functionapp"
  reserved = true
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_application_insights" "app" {
  name                = "${local.func_name}-insights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "other"
  workspace_id = data.azurerm_log_analytics_workspace.default.id
}

resource "azurerm_function_app" "func" {
  name                       = "${local.func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  version = "~4"
  os_type = "linux"
  https_only = true
  site_config {
    linux_fx_version = "node|14"
    use_32_bit_worker_process = false
    vnet_route_all_enabled    = true
  }
  app_settings = {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app.instrumentation_key
      "FUNCTIONS_WORKER_RUNTIME"       = "node"
      "WEBSITE_NODE_DEFAULT_VERSION"   = "~14"
      "WEBSITE_CONTENTOVERVNET"        = "1"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "local_file" "localsettings" {
    content     = <<-EOT
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": ""
  }
}
EOT
    filename = "../funcactive/local.settings.json"
}

resource "local_file" "localsettings2" {
    content     = <<-EOT
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "AzureWebJobsStorage": ""
  }
}
EOT
    filename = "../funccheckout/local.settings.json"
}

resource "null_resource" "publish_func"{
  depends_on = [
    azurerm_function_app_slot.checkout
  ]
  triggers = {
    index = "${timestamp()}"
  }
  provisioner "local-exec" {
    working_dir = "../funcactive"
    command     = "npm install && func azure functionapp publish ${azurerm_function_app.func.name}"
  }
}

resource "azurerm_function_app_slot" "checkout" {
  name                       = "checkout"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  app_service_plan_id        = azurerm_app_service_plan.asp.id
  function_app_name          = azurerm_function_app.func.name
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  os_type = "linux"
  version = "~4"
  app_settings = {
      "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app.instrumentation_key
      "FUNCTIONS_WORKER_RUNTIME"       = "node"
      "WEBSITE_NODE_DEFAULT_VERSION"   = "~14"
      "WEBSITE_CONTENTOVERVNET"        = "1"
  }
}

resource "null_resource" "publish_func_checkout"{
  depends_on = [
    azurerm_function_app_slot.checkout
  ]
  triggers = {
    index = "${timestamp()}"
  }
  provisioner "local-exec" {
    working_dir = "../funccheckout"
    command     = "npm install && func azure functionapp publish ${azurerm_function_app.func.name} --slot checkout"
  }
}
