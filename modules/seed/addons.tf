# Copyright (c) 2017 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module "addons_dir" {
  source = "../variable"
  value  = "${path.module}/templates/addons"
}

#
# addon specific modules
#

#
# outputs per addon module
#
# output "dummy"      # config for inactive processing
# output "defaults"   # defaults for manual config settings
# output "generated"  # generated settings (i.e. certificates)
# output "manifests"  # manifest template path
#
# all those settings will be available for the 
# manifesttemplate processing of the addon
#

module "nginx-ingress" {
  source     = "addons/nginx-ingress"
  active     = "${contains(local.selected,"nginx-ingress")}"
  cluster-lb = "${var.cluster-lb}"
  config     = "${local.configured["nginx-ingress"]}"

  versions = "${var.versions}"
  standard = "${local.standard}"

  selected = "${local.selected}"
}

module "monitoring" {
  source = "addons/monitoring"
  active = "${contains(local.selected,"monitoring")}"

  config              = "${local.configured["monitoring"]}"
  cluster_name        = "${var.cluster_name}"
  ingress_base_domain = "${var.ingress_base_domain}"
  dashboard_creds_b64 = "${module.dashboard_creds.b64}"

  tls_dir = "${var.gen_dir}/files/addons/monitoring/tls"
  ca      = "${module.apiserver.ca_cert}"
  ca_key  = "${module.apiserver.ca_key}"
}

module "dex" {
  source     = "addons/dex"
  active     = "${contains(local.selected,"dex")}"
  cluster-lb = "${var.cluster-lb}"
  config     = "${local.configured["dex"]}"

  versions = "${var.versions}"
  standard = "${local.standard}"
}

module "gardener" {
  source = "addons/gardener"
  active = "${contains(local.selected,"gardener")}"
  config = "${local.configured["gardener"]}"

  standard = "${local.standard}"

  domain_name     = "${var.domain_name}"
  etcd_service_ip = "${var.etcd_service_ip}"
  dns             = "${merge(module.route53_access_info.value,var.dns)}"
  versions        = "${var.versions}"

  tls_dir = "${var.gen_dir}/files/addons/gardener/tls"
  ca      = "${module.apiserver.ca_cert}"
  ca_key  = "${module.apiserver.ca_key}"
}

module "external-dns" {
  source = "addons/external-dns"
  active = "${contains(local.selected,"external-dns")}"
  config = "${local.configured["external-dns"]}"

  versions = "${var.versions}"

  dns_access_info = "${module.dns_access_info.value}"
  domain_filters  = "${var.domain_name}"
}

module "machine" {
  source = "addons/machine"
  active = "${contains(local.selected,"machine")}"
  config = "${local.configured["machine"]}"

  versions = "${var.versions}"

  iaas_config = "${var.iaas_config}"
  vm_info     = "${var.worker_info}"
}

#
# generic addon handling
#

#
# to add an addon add an appropriate entry to local.defaultconfig and append the key to local.addons
#

# for some unknown reasons locals cannot be used here
variable "slash" {
  default = "\""
}

module "iaas-addons" {
  source = "../variable"
  value  = "${length(var.addon_dirs) > 0 ? "${var.slash}${join("${var.slash} ${var.slash}", var.addon_dirs)}${var.slash}" : ""}"
}

locals {
  # this an explicit array to keep a distinct order for the multi-resource
  addons = [
    "dashboard",
    "nginx-ingress",
    "logging",
    "kube-lego",
    "heapster",
    "monitoring",
    "guestbook",
    "cluster",
    "dex",
    "gardener",
    "external-dns",
    "machine",
  ]

  index_dex = "${index(local.addons,"dex")}"

  empty = {
    "dashboard"     = {}
    "heapster"      = {}
    "nginx-ingress" = {}
    "kube-lego"     = {}
    "logging"       = {}
    "monitoring"    = {}
    "guestbook"     = {}
    "cluster"       = {}
    "dex"           = {}
    "gardener"      = {}
    "external-dns"  = {}
    "machine"       = {}
  }

  defaults = {
    "dashboard" = {
      basic_auth_b64    = "${module.dashboard_creds.b64}"
      dashboard_image   = "${module.versions.dashboard_image}"
      dashboard_version = "${module.versions.dashboard_version}"
      app_name          = "dashboard"
    }

    "nginx-ingress" = "${module.nginx-ingress.defaults}"
    "logging"       = {}
    "heapster"      = {}

    "kube-lego" = {
      version = "${module.versions.lego_version}"
    }

    "guestbook"    = {}
    "monitoring"   = "${module.monitoring.defaults}"
    "cluster"      = {}
    "dex"          = "${module.dex.defaults}"
    "gardener"     = "${module.gardener.defaults}"
    "external-dns" = "${module.external-dns.defaults}"
    "machine"      = "${module.machine.defaults}"
  }

  generated = {
    "nginx-ingress" = "${module.nginx-ingress.generated}"
    "monitoring"    = "${module.monitoring.generated}"
    "dex"           = "${module.dex.generated}"
    "gardener"      = "${module.gardener.generated}"
    "external-dns"  = "${module.external-dns.generated}"
    "machine"       = "${module.machine.generated}"
  }

  deploy = {
    "nginx-ingress" = "${module.nginx-ingress.deploy}"
    "monitoring"    = "${module.monitoring.deploy}"
    "dex"           = "${module.dex.deploy}"
    "gardener"      = "${module.gardener.deploy}"
    "external-dns"  = "${module.external-dns.deploy}"
    "machine"       = "${module.machine.deploy}"
  }

  subst = {
    "dex" = "empty"
  }

  dummy_tmp = {
    basic_auth_b64 = ""
    email          = ""
    version        = ""
    namespace      = ""
    app_name       = ""
  }

  extention = {
    dummy = "${merge(local.dummy_tmp, module.monitoring.dummy, module.dex.dummy, module.gardener.dummy, module.external-dns.dummy, module.nginx-ingress.dummy, module.machine.dummy)}"
    empty = {}
  }

  selected = "${keys(var.addons)}"

  configured      = "${merge(local.empty, var.addons)}"
  config          = "${merge(local.empty, local.extention, var.addons)}"
  defaultconfig   = "${merge(local.empty, local.defaults)}"
  generatedconfig = "${merge(local.empty, local.generated)}"

  standard = {
    rbac_version       = "rbac.authorization.k8s.io/v1beta1"
    deployment_version = "apps/v1beta2"

    cluster_name = "${var.cluster_name}"
    cluster_type = "${var.cluster_type}"
    ingress      = "${var.ingress_base_domain}"

    identity               = "${var.identity_domain}"
    apiserver_ca_crt_b64   = "${module.apiserver.ca_cert_b64}"
    api_aggregator_crt_b64 = "${module.aggregator.cert_pem_b64}"
    api_aggregator_key_b64 = "${module.aggregator.private_key_pem_b64}"
    etcd_client_ca_crt_b64 = "${module.etcd-client.ca_cert_b64}"
    etcd_client_crt_b64    = "${module.etcd-client.cert_pem_b64}"
    etcd_client_key_b64    = "${module.etcd-client.private_key_pem_b64}"

    nodes_cidr = "${var.nodes_cidr}"
  }

  empty_dir = "${path.module}/templates/empty"

  addon_template_dirs = {
    nginx-ingress = "${module.nginx-ingress.manifests}"
    cluster       = "${lookup(local.config["cluster"],"template_dir","${local.empty_dir}")}"
    monitoring    = "${module.monitoring.manifests}"
    dex           = "${module.dex.manifests}"
    gardener      = "${module.gardener.manifests}"
    external-dns  = "${module.external-dns.manifests}"
    machine       = "${module.machine.manifests}"
  }
}

#
# the templates are always processed for all possible addons, always in the same
# order, this allows to use a counted resource, even if then actual set of addons
# changes without potentials recreation because of the index change of an addon.
#
# non-active addons are generated into a temporary dummy location, while active
# addons are generated into the addons folder below the gen folder.
#
# the dummy config defines null values for all template vars for all addons
# It is used ONLY if the addon is inactive, this prevents errors comming from the template.
# If the addon is used only the defaults are merged, this will cause errors if
# a mandatory configuration variable for an extension is missing
#

resource "template_dir" "addons" {
  count = "${length(local.addons)}"

  source_dir      = "${lookup(local.addon_template_dirs, local.addons[count.index], "${module.addons_dir.value}/${local.addons[count.index]}/manifests")}"
  destination_dir = "${var.gen_dir}/${contains(local.selected, local.addons[count.index]) ? "assets/addons" : "tmp"}/${local.addons[count.index]}/manifests"

  #vars = "${merge(map("addon_name",local.addons[count.index]), local.standard, local.defaultconfig[local.addons[count.index]],local.generatedconfig[local.addons[count.index]],local.config[contains(local.selected, local.addons[count.index]) ? "empty" : "dummy"])}"
  vars = "${merge(map("addon_name",local.addons[count.index]), local.standard, local.defaultconfig[local.addons[count.index]],local.generatedconfig[local.addons[count.index]],local.config[contains(local.selected, local.addons[count.index]) ? lookup(local.subst, local.addons[count.index], local.addons[count.index]) : "dummy"])}"
}

resource "null_resource" "deploy" {
  count = "${length(local.addons)}"

  triggers {
    addon  = "${local.addons[count.index]}"
    active = "${contains(local.selected, local.addons[count.index])}"
    deploy = "${contains(local.selected, local.addons[count.index]) ? lookup(local.deploy,local.addons[count.index],"") : ""}"
  }

  provisioner "local-exec" {
    command = "${contains(local.selected, local.addons[count.index]) ? "${path.module}/scripts/copy_deploy '${var.gen_dir}/addons/${local.addons[count.index]}' '${lookup(local.deploy,local.addons[count.index],"")}'" : "echo ${local.addons[count.index]} inactive"}"
  }
}

output "vars-dex" {
  value = "${merge(map("addon_name",local.addons[local.index_dex]), local.standard,local.defaultconfig[local.addons[local.index_dex]],local.generatedconfig[local.addons[local.index_dex]],local.config[contains(local.selected, local.addons[local.index_dex]) ? lookup(local.subst,local.addons[local.index_dex],local.addons[local.index_dex]) : "dummy"])}"
}

#output "addon-generated" {
#  value = "${local.generated}"
#}
#output "addon-empty" {
#  value = "${local.empty}"
#}
#output "addon-dummy" {
#  value = "${local.dummy}"
#}
output "addon-config" {
  value = "${local.config}"
}
