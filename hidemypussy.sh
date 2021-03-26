#!/bin/bash

project_name="hidemypussy"
img_name=$project_name
cont_name=$project_name
docker_folder="gateway"
network_file="network.xml"
network=$project_name
tor_trans_port="9040"
tor_dns_port="5353"
tor_virt_addr="10.192.0.0/10"
gtw_ip="10.152.152.10/18"
start_file="/home/user/start"
veth_host="vmnet-host"
veth_cont="vmnet-cont"

print_help() {
    echo -e "Usage: $0 <action>

ACTIONS:
        - c, configure              Install dependencies, configure network and build gateway docker image
        - s, start                  Start the gateway
"
}

virsh_get_field() {
    echo $(virsh net-info $network | grep $1 | tr -s " " | cut -d " " -f 2)
}

if [ "$#" -eq 0 ]; then
    print_help
elif [ "$EUID" -ne 0 ]; then
    echo "Error: root access required"
else
    case $1 in
        "s" | "start")
            #check whether network and gateway have been configured
            if [ -z "$(virsh net-list --all | grep $network)" ]; then
                echo "Error: network $network not found. Did you run \"$0 configure\" first ?"
                exit
            elif [ -z "$(docker images | grep $img_name)" ]; then
                echo "Error: docker image $img_name not found. Did you run \"$0 configure\" first ?"
                exit
            fi
            if [ "$(docker ps -q -f name=$cont_name)" ]; then
                echo "Error: conatiner $cont_name is already running"
                exit
            elif [ "$(docker ps -aq -f status=exited -f name=$cont_name)" ]; then
                docker rm $cont_name
            fi
            #start $network
            network_started=$(virsh_get_field "Active")
            if [ $network_started = "no" ]; then
                virsh net-start $network
            fi
            brif=$(virsh_get_field "Bridge")
            #configure veth interfaces
            ip link add $veth_cont type veth peer name $veth_host
            brctl addif $brif $veth_host
            ip link set $veth_host up
            #start gateway on wait.sh
            docker run --rm -itd --cap-drop=ALL --name $cont_name $img_name
            pid=$(docker inspect -f '{{.State.Pid}}' $cont_name)
            #setup gateway networing inside $network
            ip link set netns $pid dev $veth_cont
            nsenter -t $pid -n ip link set $veth_cont up
            nsenter -t $pid -n ip addr add $gtw_ip dev $veth_cont
            #allow *.onion
            nsenter -t $pid -n iptables -t nat -A PREROUTING -i $veth_cont -p tcp -d $tor_virt_addr --syn -j REDIRECT --to-ports $tor_trans_port
            #redirect DNS to tor
            nsenter -t $pid -n iptables -t nat -A PREROUTING -i $veth_cont -p udp --dport 53 -j REDIRECT --to-ports $tor_dns_port
            nsenter -t $pid -n iptables -t nat -A PREROUTING -i $veth_cont -p udp --dport $tor_dns_port -j REDIRECT --to-ports $tor_dns_port
            #redirect TCP to tor
            nsenter -t $pid -n iptables -t nat -A PREROUTING -i $veth_cont -p tcp --syn -j REDIRECT --to-ports $tor_trans_port
            #start tor
            docker exec $cont_name touch $start_file
            docker attach $cont_name
            ;;
    	"c" | "configure")
            dockerfile="$docker_folder/Dockerfile"
            if [ ! -f $network_file ]; then
                echo "Error: $network_file not found"
            	exit
            elif [ ! -f $dockerfile ]; then
                echo "Error: $dockerfile not found"
                exit
            fi
            virsh net-define $network_file
            pushd $docker_folder
            docker build -t $img_name .
            ;;
        *)
            echo "Unkown action: $1"
            print_help
            ;;
    esac
fi
