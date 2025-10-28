#!/bin/bash

#colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
rest='\033[0m'
ip=$(hostname -I | awk '{print $1}')
n_i=$(ip -o -4 route show to default | awk '{print $5}')

# Detect the Linux distribution
detect_distribution() {
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            p_m="apt-get"
            [ "${ID}" = "centos" ] && p_m="yum"
            [ "${ID}" = "fedora" ] && p_m="dnf"
        else
            echo -e "${red}Unsupported distribution!${rest}"
            exit 1
        fi
    else
        echo -e "${red}Unsupported distribution!${rest}"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    detect_distribution
    sudo "${p_m}" -y update && sudo "${p_m}" -y upgrade
    local dependencies=("curl" "socat" "dnsutils")
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo -e "${yellow}${dep} is not installed. Installing...${rest}"
            sudo "${p_m}" install "${dep}" -y
        fi
    done
}

# Download bin file
download_smartdns() {
    local os=""
    local arch=""
    local download_url=""

    # Check OS
    if [ "$(uname -s)" = "Darwin" ]; then
        os="darwin"
    elif [ "$(uname -s)" = "Linux" ]; then
        os="linux"
        # Check CentOS version
        if [ -f /etc/redhat-release ]; then
            if grep -q "CentOS Linux release 7" /etc/redhat-release; then
                echo "Requires CentOS version >= 8"
                exit 1
            fi
        fi
    else
        echo "Unsupported OS"
        exit 1
    fi

    # Check architecture
    case "$(uname -m)" in
        "x86_64")
            arch="x86_64"
            ;;
        "x86")
            arch="x86"
            ;;
        "arm")
            arch="arm"
            ;;
        "arm64")
            arch="aarch64"
            ;;
        "mips")
            arch="mips"
            ;;
        "mipsel")
            arch="mipsel"
            ;;
        *)
            echo "Unsupported architecture"
            exit 1
            ;;
    esac

    # Define download URL
    download_url="https://github.com/pymumu/smartdns/releases/download/Release45/smartdns-${arch}"

    # Install smartdns if not already installed
    if ! command -v smartdns &> /dev/null; then
        if [ "$os" != "" ] && [ "$arch" != "" ]; then
            curl -L -o /usr/local/bin/smartdns "$download_url"
            chmod +x /usr/local/bin/smartdns
        else
            echo "SmartDNS does not support your OS/ARCH yet."
            exit 1
        fi
    else
        echo -e "${cyan}______________________${rest}"
        echo -e "${green}SmartDNS already installed${rest}"
    fi
}

# Function to install ACME certificate
install_acme(){
    if [[ "${ID}" == "centos" ]]; then
        "${p_m}" install cronie
        systemctl start cronie
        systemctl enable cronie
    else
        "${p_m}" install cron
        systemctl start cron
        systemctl enable cron
    fi
    
    mkdir -p /etc/smartdns
    echo -e "${purple}***********************${rest}"
    echo -en "${green}Enter Your domain name: ${rest}"
    read -r domain
    curl https://get.acme.sh | sh    
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    echo -e "${purple}**********************${rest}"
    echo -en "${green}Please enter your registration email (e.g., admin@gmail.com, or Press Enter to generate a random Gmail): ${rest}"
    read -r email
    if [[ -z "${email}" ]]; then
        mail=$(date +%s%N | md5sum | cut -c 1-16)
        email="${mail}@gmail.com"
        echo -e "${green}Gmail set to: ${yellow}${email}${rest}"
        echo -e "${purple}**********************${rest}"
        sleep 1
    fi
    ~/.acme.sh/acme.sh --register-account -m "${email}"
    ~/.acme.sh/acme.sh --issue -d "${domain}" --standalone
    ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /etc/smartdns/private.key --fullchain-file /etc/smartdns/cert.crt
    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" | sudo tee -a /etc/crontab
}

install() {
    if systemctl is-active --quiet smartdns.service; then
        echo -e "${yellow}***********************${rest}"
        echo -e "${green}Service is already installed and active.${rest}"
        echo -e "${yellow}***********************${rest}"
    else
        echo -e "${purple}***********************${rest}"
        echo -e "${cyan}Installing...${rest}"
	    check_dependencies
	    if sudo systemctl is-active --quiet smartdns; then
	        echo -e "${cyan}______________________${rest}"
	        echo -e "${green}SmartDns service is already Actived.${rest}"
	        echo -e "${cyan}______________________${rest}"
	    else
			# Download and install smartdns
			if [ ! -f "/usr/local/bin/smartdns" ]; then
                # Download and install smartdns
                download_smartdns
            else
                echo -e "${green}SmartDns binary already exists.${rest}"
            fi
			# Create smartdns configuration file
			mkdir -p /etc/smartdns
			
			cat <<EOL > /etc/smartdns/smartdns.conf
# Set listen port for UDP and TCP
bind [::]:53
bind-tcp [::]:53

# Set upstream servers
server 1.1.1.1
server-tls 8.8.8.8
EOL
		
			# Ask user whether to enable DNS over TLS (DOT)
			echo -e "${purple}***********************${rest}"
			echo -en "${green}Do you want to enable${cyan} DNS over TLS (DOT)${yellow} (domain required)${green}? (yes/no)${green}[default: ${yellow}no${green}]: ${rest}"
			read -r enable_dot
			
			if [[ $enable_dot == "yes" ]]; then
			    echo "bind-tls [::]:853@$n_i" >> /etc/smartdns/smartdns.conf
			fi
			
			# Ask user whether to enable DNS over HTTPS (DOH)
			echo -e "${purple}***********************${rest}"
			echo -en "${green}Do you want to enable${cyan} DNS over HTTPS (DOH)${yellow} (domain required)${green}? (yes/no)${green}[default: ${yellow}no${green}]: ${rest}"
            read -r enable_doh
			
			if [[ $enable_doh == "yes" ]]; then
			    echo "bind-https [::]:443@$n_i" >> /etc/smartdns/smartdns.conf
			fi
			
			# Check if any or both DOT and DOH are enabled
			if [[ $enable_dot == "yes" || $enable_doh == "yes" ]]; then
			    echo "bind-cert-key-file /etc/smartdns/private.key" >> /etc/smartdns/smartdns.conf
			    echo "bind-cert-file /etc/smartdns/cert.crt" >> /etc/smartdns/smartdns.conf
			    # Install ACME certificate
			    install_acme
			fi
	
			# Create systemd service file
			cat <<EOL > /etc/systemd/system/smartdns.service
[Unit]
Description=SmartDNS Service
After=network.target

[Service]
ExecStart=/usr/local/bin/smartdns -R -f -c /etc/smartdns/smartdns.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL
		
			# Stop and disable systemd-resolved
			systemctl stop systemd-resolved
			systemctl disable systemd-resolved >/dev/null 2>&1
			
			# Update & backup resolv.conf
	        cp /etc/resolv.conf /etc/resolv.conf.bak
			echo "nameserver 127.0.0.1" > /etc/resolv.conf
			
			# Enable and start smartdns
			systemctl enable smartdns
			systemctl start smartdns
			
			check
			show_dns
		fi
	fi
}

# Add Domain list
add_website() {
    if [ ! -f "/etc/systemd/system/smartdns.service" ]; then
        echo -e "${purple}***********************${rest}"
        echo -e "${red}The service is not installed.${rest}"
        echo -e "${purple}***********************${rest}"
        return
    fi
    # Get domain list from user separated by comma
    echo -e "${purple}***********************${rest}"
    echo -en "${green}Enter domain list separated by comma [${cyan}example${green}: ${yellow}kmplayer.com,ebay.com${green}]:${rest} "
    read -r add_website
    echo -e "${purple}***********************${rest}"
    
    # Split domain list by comma
    IFS=',' read -ra domains <<< "$add_website"
    
    # Create smartdns configuration file
    config_file="/etc/smartdns/smartdns.conf"
    
    # Set Domain List section header and ptr
    grep -q "^# Domain List$" "$config_file" || echo "# Domain List" >> "$config_file"
    grep -q "^expand-ptr-from-address yes$" "$config_file" || echo "expand-ptr-from-address yes" >> "$config_file"
    
    # Variable to count successful additions
    successful=0
    
    # Variable to count failed additions
    failed=0
    
    # Iterate over domains
    for domain in "${domains[@]}"; do
        # Check if the domain is valid
        if [[ ! $domain =~ ^[a-zA-Z0-9.-]+$ ]]; then
            echo -e "${red}Invalid domain: $domain. ${rest}❌"
            echo ""
            ((failed++))
            continue
        fi
        
        # Resolve IP addresses for the domain
        ips=$(dig +short "$domain")
        
        # Check if IP addresses are found
        if [ -z "$ips" ]; then
            echo -e "${yellow}No IP found for: ${green}$domain ${rest}❌"
            echo ""
            ((failed++))
            continue
        fi
        
        # Check if the domain already exists in the configuration file
        if grep -q "address /$domain/" "$config_file"; then
            echo -e "${yellow}Domain ${green}$domain ${yellow}already exists. ❌"
            echo ""
            ((failed++))
        else
            # Add domain rules to the configuration file
            ip_list=$(echo "$ips" | tr '\n' ',' | sed 's/,$//')
            echo "address /$domain/$ip_list" >> "$config_file"
            echo -e "${green}Domain ${yellow}$domain ${green}successfully added. ${rest}✅"
            echo ""
            ((successful++))
        fi
    done
    
    echo -e "${purple}***********************${rest}"
    echo -e "${green}Successful additions: $successful ${rest}"
    echo -e "${yellow}Failed additions: $failed ${rest}"
    echo -e "${purple}***********************${rest}"
    
    # Restart smartdns service
    systemctl restart smartdns
}

# Show sites
show_sites() {
    if [ ! -f "/etc/systemd/system/smartdns.service" ]; then
        echo -e "${purple}***********************${rest}"
        echo -e "${red}The service is not installed.${rest}"
        echo -e "${purple}***********************${rest}"
        return
    fi
    echo -e "${purple}***********************${rest}"
    echo -e "${cyan}List of configured sites:${rest}"
    echo ""

    # Use a counter variable
    counter=1
    # Loop through each line containing "address" in smartdns.conf
    while read -r line; do
        # Extract the website name from the line
        website=$(echo "$line" | awk '{print $2}' | sed 's#^\/##')
        # Print the counter and website name
        echo "${counter}. ${website}"
        # Increment the counter
        ((counter++))
    done < <(grep "^address" /etc/smartdns/smartdns.conf)

    echo ""
    # Count the number of configured sites
    num_sites=$(grep -c "^address" /etc/smartdns/smartdns.conf)
    echo -e "${yellow}Total Sites: ${cyan}[$num_sites]${rest}"
    echo -e "${purple}========================${rest}"
}

# Update list of Domain Ips
update_domain_ips() {
    if [ ! -f "/etc/systemd/system/smartdns.service" ]; then
        echo -e "${purple}***********************${rest}"
        echo -e "${red}The service is not installed.${rest}"
        echo -e "${purple}***********************${rest}"
        return
    fi
    
    local config_file="/etc/smartdns/smartdns.conf"
    local temp_file="$(mktemp)"
    local updated_domains=0
    
    cp "$config_file" "$temp_file"
    
    while IFS= read -r line; do
        if [[ $line =~ ^address\ \/([a-zA-Z0-9.-]+)\/(.+)$ ]]; then
            domain="${BASH_REMATCH[1]}"
            old_ips="${BASH_REMATCH[2]}"
            
            new_ips=$(dig +short "$domain" | tr '\n' ',' | sed 's/,$//')
            
            if [[ "$old_ips" != "$new_ips" ]]; then
                sed -i "s/$domain\/$old_ips/$domain\/$new_ips/" "$temp_file"
                echo -e "${green}Domain ${yellow}$domain${green} updated with new IPs: ${yellow}$new_ips ${rest}"
                ((updated_domains++))
            else
                echo -e " ${green}Domain ${yellow}$domain ${green}is already up to date.${rest}"
            fi
        fi
    done < "$config_file"
    
    mv "$temp_file" "$config_file"
    
    systemctl restart smartdns
    echo -e "${purple}***********************${rest}"
    echo -e "${green}Updated ${yellow}$updated_domains domains.${rest}"
    echo -e "${purple}***********************${rest}"
}

# Delete Sites
remove_sites() {
    if [ ! -f "/etc/systemd/system/smartdns.service" ]; then
        echo -e "${purple}***********************${rest}"
        echo -e "${red}The service is not installed.${rest}"
        echo -e "${purple}***********************${rest}"
        return
    fi
    # Show configured sites with numbers
    show_sites

    # Ask user for the numbers of the sites to delete
    echo -en "${green}Enter the ${yellow}numbers${green} of the sites you want to delete (separated by comma) [${cyan}example:${yellow} 1,3,4${green}] :${rest}"
    read -r site_numbers
    echo -e "${purple}***********************${rest}"

    # Split the input into an array based on commas
    IFS=',' read -r -a numbers_array <<< "$site_numbers"

    # Create a temporary file to store modified configuration
    temp_file="$(mktemp)"

    # Copy the original SmartDNS configuration to the temporary file
    cp /etc/smartdns/smartdns.conf "$temp_file"

    # Loop through the array of numbers
    for number in "${numbers_array[@]}"; do
        # Validate user input
        if [[ ! "$number" =~ ^[0-9]+$ ]]; then
            echo -e "${red}Invalid input. Please enter numbers separated by comma.${rest}"
            return
        fi

        # Get the domain of the site
        site_domain=$(grep "^address" /etc/smartdns/smartdns.conf | sed -n "${number}p" | awk '{print $2}' | sed 's#^\/##')

        # Check if the site exists
        if [ -z "$site_domain" ]; then
            echo -e "${red}Site number $number not found.${rest}"
            continue
        fi

        # Delete the line from the temporary configuration file using sed
        sed -i "\|^address.*$site_domain|d" "$temp_file"

        echo -e "${green}Site ${yellow}$site_domain${green} (number $number) deleted successfully.${rest}"
        echo ""
    done

    # Replace the original configuration file with the modified temporary file
    mv "$temp_file" /etc/smartdns/smartdns.conf

    # Restart smartdns service
    systemctl restart smartdns
}

# Uninstall function
uninstall() {
    if [ ! -f "/etc/systemd/system/smartdns.service" ]; then
        echo -e "${purple}***********************${rest}"
        echo -e "${red}The service is not installed.${rest}"
        echo -e "${purple}***********************${rest}"
        return
    fi
    
    # Restore the resolv.conf backup
    mv /etc/resolv.conf.bak /etc/resolv.conf
    
    # Stop and disable the service
    sudo systemctl stop smartdns.service
    sudo systemctl disable smartdns.service 2>/dev/null

    # Remove service file
    sudo rm /etc/systemd/system/smartdns.service
    rm -rf /etc/smartdns
    rm -rf /root/.acme.sh/"${domain}"_*
    systemctl restart systemd-resolved
    echo -e "${purple}***********************${rest}"
    echo -e "${green}Uninstallation completed successfully.${rest}"
    echo -e "${purple}***********************${rest}"
}

# Show Dns (dot - doh)
show_dns() {
    if systemctl is-active --quiet smartdns.service; then
        echo -e "${purple}***********************${rest}"
        if [[ $enable_doh == "yes" ]]; then
            echo -e "${green} Dns over Https${rest}"
            echo -e "${yellow}DOH${cyan}: https://$domain/dns-query${rest}"
            echo ""
        fi
        if [[ $enable_dot == "yes" ]]; then
            echo -e "${green} Dns over Tls${rest}"
            echo -e "${yellow}DOT${cyan}: $domain${rest}"
            echo ""
        fi
        echo -e "${green} DNS over UDP & TCP${rest}"
        echo -e "${yellow}DNS${cyan}: $ip${rest}"
        echo -e "${purple}***********************${rest}"
    fi
}

# Check install
check() {
    if systemctl is-active --quiet smartdns.service; then
        echo -e "${purple}***********************${rest}"
        echo -e "${cyan} [SMART DNS ${green}is Active]${rest}"
    else
        echo -e "${purple}***********************${rest}"
        echo -e "${yellow}[SMART DNS ${red}Not Active]${rest}"
    fi
}

# Main menu
main_menu() {
    clear
    echo -e "${cyan}By --> Peyman * Github.com/Ptechgithub * ${rest}"
    echo ""
    check
    echo -e "${purple}***********************${rest}"
    echo -e "${purple}*      ${yellow}SMART DNS ${purple}     *${rest}"
    echo -e "${purple}***********************${rest}"
    echo -e "${yellow} [1] ${green}Install          ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [2] ${green}Add sites        ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [3] ${green}Show sites       ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [4] ${green}Delete sites     ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [5] ${green}Update sites IPs ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [6] ${green}Uninstall        ${purple}*${rest}"
    echo -e "${purple}                      * ${rest}"
    echo -e "${yellow} [0] ${green}Exit             ${purple}*${rest}"
    echo -e "${purple}***********************${rest}"
    echo -en "${cyan}Enter your choice: ${rest}"
    read -r choice
    case "$choice" in
        1)
            install
            ;;
        2)
            add_website
            ;;
        3)
            show_sites
            ;;
        4)
            remove_sites
            ;;
        5)
            update_domain_ips
            ;;
        6)
            uninstall
            ;;
        0)
            echo -e "${cyan}Goodbye!🖐${rest}"
            exit
            ;;
        *)
            echo -e "${red}×××××××××××××××××××××××${rest}"
            echo -e "${red}Invalid choice. Please select a valid option.${rest}"
            echo -e "${red}×××××××××××××××××××××××${rest}"
            ;;
    esac
}
main_menu