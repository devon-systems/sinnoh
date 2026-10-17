resource "cloudflare_dns_record" "snarled_at_apex_a" {
  zone_id  = local.zones.snarled_at
  name     = "snarled.at"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "snarled_at_www_cname" {
  zone_id  = local.zones.snarled_at
  name     = "www.snarled.at"
  type     = "CNAME"
  content  = "snarled.at"
  proxied  = true
  ttl      = 1
  tags     = []
  settings = { flatten_cname = false }
}
