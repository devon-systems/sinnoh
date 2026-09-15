resource "cloudflare_dns_record" "aly_town_apex_a" {
  zone_id  = local.zones.aly_town
  name     = "aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_vault_a" {
  zone_id  = local.zones.aly_town
  name     = "vault.aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_skytrace_a" {
  zone_id  = local.zones.aly_town
  name     = "skytrace.aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_slingshot_a" {
  zone_id  = local.zones.aly_town
  name     = "slingshot.aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_snarled_a" {
  zone_id  = local.zones.aly_town
  name     = "snarled.aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_atbbs_a" {
  zone_id  = local.zones.aly_town
  name     = "atbbs.aly.town"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "aly_town_skytrace_atproto_txt" {
  zone_id  = local.zones.aly_town
  name     = "_atproto.skytrace.aly.town"
  type     = "TXT"
  content  = "\"did=did:plc:jwxdvd2mdtdq7la7toiy2rjc\""
  proxied  = false
  ttl      = 1
  tags     = []
  settings = {}
}
