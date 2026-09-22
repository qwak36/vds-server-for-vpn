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

`apt install wireguard`

`wg genkey | tee /etc/wireguard/server_privatekey | wg pubkey | tee /etc/wireguard/server_publickey`
Generating server keys  

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

In string of PostUp and Postdown, replace network interface eth0 in your mine, if necessary
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
