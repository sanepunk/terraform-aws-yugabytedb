#!/bin/bash

dnf install -y python3.11 wget perl-Digest-SHA
ln -sf /usr/bin/python3.11 /usr/bin/python
YB_HOME=/home/ec2-user/yugabyte-2026.1.2.0
cd /home/ec2-user

wget https://software.yugabyte.com/releases/2026.1.2.0/yugabyte-2026.1.2.0-b137-linux-x86_64.tar.gz
echo "$(curl -L https://software.yugabyte.com/releases/2026.1.2.0/yugabyte-2026.1.2.0-b137-linux-x86_64-tar.gz.sha) *yugabyte-2026.1.2.0-b137-linux-x86_64.tar.gz" | shasum --check && \
tar xvfz yugabyte-2026.1.2.0-b137-linux-x86_64.tar.gz && cd yugabyte-2026.1.2.0/ && \
chown -R ec2-user:ec2-user /home/ec2-user && \
$YB_HOME/bin/post_install.sh



# ./bin/yb-master \
#     --master_addresses "${MASTER_ADDRS}" \
#     --rpc_bind_addresses "${NODE_IP}:7100" \
#     --replication_factor 3 \
#     --fs_data_dirs "/home/ec2-user" \
#     --placement_cloud aws \
#     --placement_region ap-south-1 \
#     --placement_zone "${AZ}" \
#     >& /home/ec2-user/yb-master.out &


# ./bin/yb-tserver \
#     --tserver_master_addrs "${MASTER_ADDRS}" \
#     --rpc_bind_addresses "${NODE_IP}:9100" \
#     --enable_ysql \
#     --pgsql_proxy_bind_address "${NODE_IP}:5433" \
#     --cql_proxy_bind_address "${NODE_IP}:9042" \
#     --fs_data_dirs "/home/ec2-user" \
#     --placement_cloud aws \
#     --placement_region ap-south-1 \
#     --placement_zone "${AZ}" \
#     >& /home/ec2-user/yb-tserver.out &



cat > /etc/systemd/system/yb-master.service <<EOF
[Unit]
Description=YugabyteDB Master
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=$YB_HOME
ExecStart=$YB_HOME/bin/yb-master \
    --master_addresses "${MASTER_ADDRS}" \
    --rpc_bind_addresses "${NODE_IP}:7100" \
    --replication_factor 3 \
    --fs_data_dirs "/home/ec2-user" \
    --placement_cloud aws \
    --placement_region ap-south-1 \
    --placement_zone "${AZ}" 
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=12000

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/yb-tserver.service <<EOF
[Unit]
Description=YugabyteDB TServer
After=network-online.target yb-master.service
Wants=network-online.target

[Service]
User=ec2-user
Group=ec2-user
WorkingDirectory=$YB_HOME
ExecStart=$YB_HOME/bin/yb-tserver \
    --tserver_master_addrs "${MASTER_ADDRS}" \
    --rpc_bind_addresses "${NODE_IP}:9100" \
    --enable_ysql \
    --pgsql_proxy_bind_address "${NODE_IP}:5433" \
    --cql_proxy_bind_address "${NODE_IP}:9042" \
    --fs_data_dirs "/home/ec2-user" \
    --placement_cloud aws \
    --placement_region ap-south-1 \
    --placement_zone "${AZ}" 
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=12000

[Install]
WantedBy=multi-user.target
EOF


systemctl daemon-reload
systemctl enable --now yb-master yb-tserver