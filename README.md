# qbittorrent-gluetun-protonvpn docker compose
qbittorrent and gluetun docker using proton vpn

* Use proton vpn, wireguard configuration
* forward port from proton vpn to qbittorrent, so that qbittorrent uses the fowarded port for torrenting. This is done by executing qbit.sh when a new port is forwarded
* update the volume path for gluetun to point to the location of the gluetun config folder (used by gluetun for creating work files), qbit.sh, qbittorrent config folder and qbittorrent downloads folder
* update the qbittorrent api key in qbit.sh [API_KEY="get api key from qbittorrent ui"] qbittorrent UI->Tools->Options->Web UI->API KEy
* create a folder scripts under the config folder of the qbittorrent. Copy on_download_completed.sh into the scripts folder
* update qbittorrent UI->Tools->Options->Downloads->Run on torrent finished: ```/bin/bash /config/scripts/on_download_completed.sh "%L" "%F" "%I"```
* http proxy server available on port 8888
* qbittorrent web ui available on port 6520

Note: 
1. After qbittorrent starts, log in to the UI and generate API key and update in the qbit.sh
2. Update qbittorrent to bind to tun0 or whatever name that is generated for the vpn tunnel. qbittorrent UI->Tools->Options->Advanced->Network Inferface
to start  

docker compose up
