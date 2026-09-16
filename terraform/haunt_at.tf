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
