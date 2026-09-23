# vds-server-for-vpn
My VDS server for VPN, Reverse Proxy, AD Block

# Add SSH authorization in our server

`sudo apt install openssh-server` 
Install SSH in server

`echo "your-ssh-key" > ~/.ssh/authorized_keys`
Add a key to our server

`echo "your-another-ssh-key" >> ~/.ssh/authorized_keys`
Add an another key to our server

# Install Wireguard for VPN

```bash
sudo apt install wireguard
```

`wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey | tee /etc/wireguard/server_publickey`
Generating the server keys  

`chmod 600 /etc/wireguard/server_privatekey`
Set permissions for the private key

`touch /etc/wireguard/wg0.conf`
Create a config file for server

this is:
```bash
[Interface]
PrivateKey = <server_privatekey>
Address = 10.0.0.1/24
ListenPort = 51830
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```
We insert in config file

In string of PostUp and Postdown, replace network interface eth0 in your mine, if necessary.
Find your mine network interface can with help `ip a`

Insert the contents of the `/etc/wireguard/server_privatekey` file instead of `<server_privatekey>`.  
  
Configure IP forwarding:  
`echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf`
`sysctl -p`

We enable the systemd daemon with WireGuard:  
`systemctl enable wg-quick@wg0.service`
`systemctl start wg-quick@wg0.service`
`systemctl status wg-quick@wg0.service`

We create the client keys:  
`wg genkey | tee /etc/wireguard/client_privatekey | wg pubkey | tee /etc/wireguard/client_publickey`

Add the following to the client server config:  
`touch /etc/wireguard/wg0.conf`  
```bash  
[Peer]
PublicKey = <client_publickey>  
AllowedIPs = 10.0.0.2/32  
```  

Replace `<client_publickey>` with the contents of the file `/etc/wireguard/client_publickey`  
  
We reload the systemd service with wireguard:  
`systemctl restart wg-quick@wg0`
`systemctl status wg-quick@wg0`

On the local machine (for example, on a laptop), we create a text file with the client configuration:  
`touch client_wb.conf`
We create a file for client configuration
```bash
[Interface]
PrivateKey = <client_privatekey>
Address = 10.0.0.2/32
DNS = 8.8.8.8

[Peer]
PublicKey = <server_publickey>
Endpoint = <server_ip>:51830
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 20
```
Now client_wb.conf export in wireguard app in PC or phone

# Installing AdGuard Home
AdGuard Home acts as a **local filtering DNS server** and an **AD/Tracker blocker**.
```bash
# We disable the built‑in DNS resolver. 
systemctl stop systemd-resolved 
systemctl disable systemd-resolved 

# We set a temporary external DNS so that the server doesn’t lose connection. 
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

Official auto‑installation script
```bash
curl -s -S -L lhttps://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
```

Open the browser on your PC and go to the address:
`[http://72.56.100.12:3000](http://72.56.100.12:3000)`

In your VPN settings, set our new DNS server.
# Deploying Nginx on the server
We will install Nginx on the VDS primarily as a reverse proxy server (Reverse Proxy).

1. Convenient access to web panels via the standard port.
Without Nginx, to access the AdGuard Home web interface, you would need to enter the IP address with a non‑standard port specified:
http://<server_IP>:3000

With Nginx configured, you can simply access it using the IP address or domain via the standard port 80 (HTTP) or 443 (HTTPS):
http://<IP_server>/

Nginx receives this request on port 80 and, unnoticed by you, redirects it inside the server to 10.0.0.1:3000 (where AdGuard Home is listening).

```bash
sudo apt install nginx 
```

```bash
systemctl status nginx
```

_(The status must be `active (running)`)_. if open IP our VDS (`[http://72.56.100.12](http://72.56.100.12)`) in browser, will see standart a page _"Welcome to nginx!"_.

Settings Reverse Proxy for AdGuard Home
Let’s make it so that Nginx takes the AdGuard Home control panel from the local port `3000` and serves it on the standard HTTP port (`80`).
```bash
nano /etc/nginx/sites-available/adguard
```

Insert the following settings into it (replace `<ip-server>` with your VDS IP):
```bash
server {
    listen 80;
    server_name <ip-server>; # your ip or domain
    
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    
        # Support WebSockets (It is necessary for updating statistics in real time.)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        }
    }
```

```bash
ln -s /etc/nginx/sites-available/adguard /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
```

Check configuration Nginx on errors:
```bash
nginx -t
```
 
reload nginx
```bash
systemctl restart nginx
```

