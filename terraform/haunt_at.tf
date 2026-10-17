resource "cloudflare_dns_record" "haunt_at_apex_a" {
  zone_id  = local.zones.haunt_at
  name     = "haunt.at"
  type     = "A"
  content  = local.sunnyshore
  proxied  = true
  ttl      = 1
  tags     = []
  settings = {}
}

resource "cloudflare_dns_record" "haunt_at_www_cname" {
  zone_id  = local.zones.haunt_at
  name     = "www.haunt.at"
  type     = "CNAME"
  content  = "haunt.at"
  proxied  = true
  ttl      = 1
  tags     = []
  settings = { flatten_cname = false }
}
