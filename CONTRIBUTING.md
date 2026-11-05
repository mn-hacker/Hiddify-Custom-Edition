<!-- watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only) -->

# Before Anything Else...
We are looking for contributors for this project. Please get in touch through https://watashi.cyou
```
git clone --recurse-submodules -j8 git://github.com/mn-hacker/Watashi-Manager.git

```
Basic tutorial on how to contibute to Watashi Manager is [here](https://watashi.cyou)

We need several type of helps:
- Introducing our panel (we don't have any big media 😦)
- Python developer
- Rust developer (We do not want an high level rust developer. We just want to have someone who is familiar with rust and java script for a one day task)
- Kotlin developer
- Content providers
- Services (for buying)

If you can help us, please dont hesitate to contact us through https://watashi.cyou



# Watashi-Manager Directory Structure
#### ```/common/```
This directory contains commonly used scripts for various tasks such as project installation, daily operations, firewall rule management, and more. These scripts provide essential functionality across different components of the project.

#### ```/haproxy/```
This directory contains installation/initialization/configuration scripts of the [HAProxy](https://www.haproxy.org/) project.

Watashi Manager utilizes HAProxy as its primary traffic load balancer and routing tool.

There are several Jinja2 (.j2) files, which are HAProxy configuration files. These files are used based on the panel configuration settings.

#### ```/nginx/```
This directory contains installation/initialization/configuration scripts of the [Nginx](https://nginx.org/en/) project.

Watashi Manager utilizes Nginx as its secondary load balancer and reverse proxy, alongside HAProxy.

#### ```/acme.sh/```
This directory contains installation scripts for the acme.sh project and additional scripts responsible for issuing SSL certificates for panel domains.

#### ```/xray/```
This directory contains installation/initialization scripts of the [Xray-core](https://github.com/XTLS/Xray-core).

The configs directory contains Xray's config files, which are Jinja2 (.j2) files. These config files are dynamically generated based on the panel configurations.

#### ```/singbox/```
This direcotry contails installation/initialization scripts of the [Sing-box](https://github.com/SagerNet/sing-box).

The configs directory contains Sing-box's config files, which are Jinja2 (.j2) files. These config files are dynamically generated based on the panel configurations.

#### ```/watashi-panel/```
This directory contains installation scripts of the [Watashi Panel](https://github.com/mn-hacker/watashi-panel).

#### ```/other/```
This directory contains some scripts for installing and initialization other tools that Watashi Manager needs:
```bash
├── deprecated             # Deprecated tools
├── mysql                  # MySQL installation/initialization scripts (Project database)
├── redis                  # Redis installation/initialization scripts (Project cache database)
├── speedtest              # Speedtest-related files
├── ssfaketls              # Shadowsocks faketls (obfs-server)
├── ssh                    # SSH proxy management installation/initialization scripts (ssh-liberty)
├── telegram               # Telegram mtproto installation/initialization scripts
├── v2ray                  # V2ray shadowsocks installation/initialization scripts (deprecated)
├── warp                   # Warp installation/initialization scripts
└── wireguard              # WireGuard installation/initialization scripts
```
