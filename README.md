# vds-server-for-vpn
My VDS server for VPN, Reverse Proxy, AD Block

sudo apt update && apt upgrade ## update apt


sudo apt install openssh-server ## install ssh in our server
echo "your-ssh-key" > ~/.ssh/authorized_keys ## add ssh-key in our server
echo "your-ssh-key" >> ~/.ssh/authorized_keys ## if you want to add another ssh-key

