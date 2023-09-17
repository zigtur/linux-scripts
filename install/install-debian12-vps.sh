apt update && apt upgrade -y && apt install fail2ban nftables unattended-upgrades apt-listchanges

# Configure autoupdate
## Setting autoupdates apt
cat << EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "30";
EOF

systemctl restart unattended-upgrades
systemctl enable unattended-upgrades

# Configure Firewall and Fail2ban
## Setting nftables
cat << EOF > /etc/nftables/fail2ban.conf
#!/usr/sbin/nft -f

# Use ip as fail2ban doesn't support ipv6 yet
table ip fail2ban {
        chain input {
                # Assign a high priority to reject as fast as possible and avoid more complex rule evaluation
                type filter hook input priority 100;
        }
}
EOF

cat << EOF > /etc/nftables.conf
#!/usr/sbin/nft -f

flush ruleset

include "/etc/nftables/fail2ban.conf"

table inet firewall {
    chain inbound_ipv4 {
        icmp type echo-request limit rate 5/second accept
        tcp dport { 22 } accept
    }
    chain inbound_ipv6 {
        icmpv6 type { nd-neighbor-solicit, nd-router-advert, nd-neighbor-advert } accept
        icmpv6 type echo-request limit rate 5/second accept
    }
    chain inbound {                                                              
        type filter hook input priority 0; policy drop;
        ct state vmap { established : accept, related : accept, invalid : drop } 
        iifname lo accept
        meta protocol vmap { ip : jump inbound_ipv4, ip6 : jump inbound_ipv6 }

        # Uncomment to enable logging of denied inbound traffic
        # log prefix "[nftables] Inbound Denied: " counter drop
    }                                                                            
                                                                                 
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    # no need to define output chain, default policy is accept if undefined.
}
EOF

## Configure fail2ban on SSH
### Link fail2ban to Nftables
cat << EOF > /etc/fail2ban/action.d/nftables-common.local
[Init]
# Definition of the table used
nftables_family = ip
nftables_table  = fail2ban

# Drop packets 
blocktype       = drop

# Remove nftables prefix. Set names are limited to 15 char so we want them all
nftables_set_prefix =
EOF

### Activate sshd monitoring with journalctl (systemctl)
cat << EOF > /etc/fail2ban/jail.d/defaults-debian.conf
[sshd]
enabled = true
backend = systemd
EOF

### Define behaviour nftables
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]

# configure nftables
banaction = nftables-multiport
chain     = input
EOF

## Restart and persistence
systemctl restart nftables
systemctl restart fail2ban
systemctl enable nftables 
systemctl enable fail2ban 