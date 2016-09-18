#!/bin/bash
# CTFAutoInstall

# Copyright (C) 2016 Dustin Lee
# This work makes heavy use from the previous work of
# David Reguera García - dreg@buguroo.com & David Francos Cuartero - dfrancos@buguroo.com
# from Buguroo Offensive Security <https://buguroo.com/>
# See https://github.com/buguroo/cuckooautoinstall

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

source /etc/os-release

# Configuration variables. You can override these in config.
SUDO="sudo"
TMPDIR=$(mktemp -d)
RELEASE=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CTF_USER="ctf"
CTF_DIR="/ctfscoreboard/"
CUSTOM_PKGS=""
#ORIG_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd  )
MYSQL_PASS=`cat /dev/urandom | LC_CTYPE=C tr -dc 'abcdefghijklmnopqrstuvwxyz0123456789' | fold -w 10 | head -n 1`
SEC_KEY=`cat /dev/urandom | LC_CTYPE=C tr -dc 'abcdefghijklmnopqrstuvwxyz0123456789' | fold -w 8 | head -n 1`
CTF_REPO="https://github.com/dlee35/ctfscoreboard.git"

LOG=$(mktemp)
UPGRADE=false

declare -a packages
declare -a python_packages

packages["debian"]="python-dev git libmysqlclient-dev nginx python-pip mysql-server"
packages["ubuntu"]="python-dev git libmysqlclient-dev nginx python-pip mysql-server"
python_packages=(Flask Flask-RESTful Flask-SQLAlchemy Jinja2 MarkupSafe SQLAlchemy Werkzeug aniso8601 argparse itsdangerous pbkdf2 python-dateutil pytz six wsgiref Flask-Scss Flask-Testing mysql-python uwsgi)

# Pretty icons
log_icon="\e[31m✓\e[0m"
log_icon_ok="\e[32m✓\e[0m"
log_icon_nok="\e[31m✗\e[0m"

print_copy(){
cat <<EO
┌─────────────────────────────────────────────────────────┐
│                   CTFAutoInstall 0.2                    │
│             Dustin Lee - <dlee35@gmail.com>             │
└─────────────────────────────────────────────────────────┘
EO
}

check_viability(){
    [[ $UID != 0 ]] && {
        type -f $SUDO || {
            echo "You're not root and you don't have $SUDO, please become root or install $SUDO before executing $0"
            exit
        }
    } || {
        SUDO=""
    }

    [[ ! -e /etc/debian_version ]] && {
        echo  "This script currently works only on debian-based (debian, ubuntu...) distros"
        exit 1
    }
}

print_help(){
    cat <<EOH
Usage: $0 [--verbose|-v] [--help|-h]

    --verbose   Print output to stdout instead of temp logfile
    --help      This help menu

EOH
    exit 1
}

setopts(){
    optspec=":hv-:"
    while getopts "$optspec" optchar; do
        case "${optchar}" in
            -)
                case "${OPTARG}" in
                    help) print_help ;;
                    verbose) LOG=/dev/stdout ;;
                esac;;
            h) print_help ;;
            v) LOG=/dev/stdout;;
        esac
    done
}

run_and_log(){
    $1 &> ${LOG} && {
        _log_icon=$log_icon_ok
    } || {
        _log_icon=$log_icon_nok
        exit_=1
    }
    echo -e "${_log_icon} ${2}"
    [[ $exit_ ]] && { echo -e "\t -> ${_log_icon} $3";  exit; }
}

cdctf(){
    eval cd ~${CTF_USER}
    return 0
}

cdctfdir() {
   eval cd ~${CTF_USER}${CTF_DIR}
   return 0
}

create_ctf_user(){
    $SUDO adduser  --disabled-password -gecos "" ${CTF_USER}
    $SUDO usermod -aG www-data ${CTF_USER}
    return 0
}

clone_ctf(){
    cdctf
    $SUDO git clone ${CTF_REPO}
    $SUDO chown -R ${CTF_USER}:${CTF_USER} ctfscoreboard
    cd $TMPDIR
    return 0
}

create_mysql(){
    cdctfdir
    $SUDO mysql -uroot -p${MYSQL_PASS} -e'create database db;'
    $SUDO python main.py createdb
    cd $TMPDIR
    return 0
}

stage_mysql(){
    $SUDO echo mysql-server mysql-server/root_password select ${MYSQL_PASS} | debconf-set-selections
    $SUDO echo mysql-server mysql-server/root_password_again select ${MYSQL_PASS} | debconf-set-selections
    return 0
}

fix_config(){
    cdctfdir
    $SUDO sed -i -e "17s/.*/SQLALCHEMY_DATABASE_URI\ \=\ \'mysql:\/\/root:${MYSQL_PASS}@localhost\/db\'/" \
    -e "19s/.*/SECRET_KEY\ \=\ \'${SEC_KEY}\'/" \
    -e "22s/.*/TEAM_SECRET_KEY\ \=\ \'HaXX0r\'/" -e "s/\ Dev//" \
    -e "s/TEAMS\ \=\ True/TEAMS\ \=\ False/" config.py
    $SUDO /bin/bash -c 'echo "SESSION_COOKIE_SECURE = False" >> config.py'
    cd $TMPDIR
    return 0
}

fix_nginx(){
    cdctfdir
    $SUDO sed -i -e 's/opt\//home\/ctf\/ctf/' doc/nginx.conf
    $SUDO cp doc/nginx.conf /etc/nginx/sites-available/ctf
    $SUDO rm /etc/nginx/sites-enabled/default
    $SUDO ln -s /etc/nginx/sites-available/ctf /etc/nginx/sites-enabled/
    cd $TMPDIR
    return 0
}

fix_uwsgi(){
    cdctfdir
    $SUDO sed -i -e 's/opt\//\/home\/ctf\/ctf/' -e 's/^virt/\#virt/' \
    -e 's/nobody/root/' -e 's/nogroup/root/' \
    -e 's/^plug/\#plug/' doc/uwsgi.ini
    $SUDO mkdir -p /var/log/uwsgi/app/
    $SUDO touch /var/log/uwsgi/app/uwsgi.log
    cd $TMPDIR
    return 0
}

enable_ufw(){
    $SUDO /bin/bash -c 'echo "y^M" | ufw enable'
    $SUDO /bin/bash -c 'ufw allow 22 && ufw allow 80'
    return 0
}

pip_install(){
    # TODO: Calling upgrade here should be optional.
    # Unless we make all of this into a virtualenv, which seems like the
    # correct way to follow
    for package in ${python_packages[@]}; do echo $package; $SUDO pip install ${package} --upgrade; done
    return 0
}

start_server(){
    cdctfdir
    $SUDO service nginx restart
    $SUDO uwsgi --uid root --ini doc/uwsgi.ini
    cd $TMPDIR
    return 0
}

install_packages(){
    $SUDO apt-get update
    $SUDO apt-get install -y ${packages["${RELEASE}"]}
    $SUDO apt-get install -y $CUSTOM_PKGS
    $SUDO apt-get -y install
    return 0
}

# Begin
print_copy
check_viability
setopts ${@}

echo "Logging enabled on ${LOG}"

# Install packages
run_and_log stage_mysql "Preparing for MySQL install" "Something went wrong, please look at the log file"
run_and_log install_packages "Installing packages ${packages[$RELEASE]}" "Something failed installing packages, please look at the log file"

# Install python packages
echo $python_packages
run_and_log pip_install "Installing python packages" "Something failed install python packages, please look at the log file"

# Create user and clone repos
run_and_log create_ctf_user "Creating ctf user" "Could not create ctf user"
run_and_log clone_ctf "Cloning ctf repository" "Failed"

# Configuration
run_and_log fix_nginx "Configuring nginx reverse-proxy" "Failed"
run_and_log fix_uwsgi "Tuning uwsgi.ini" "Failed"
run_and_log fix_config "Adjusting config.py for the new environment" "Failed"
run_and_log enable_ufw "Enabling UFW for SSH and HTTP only" "Failed"
run_and_log create_mysql "Creating new database for the CTF environment" "Failed"
run_and_log start_server "Server started successfully" "Failed"
echo "Your mysql password is: $MYSQL_PASS"
echo "Your secret key is: $SEC_KEY"
echo "Please write down these values!"
echo "Script complete. Have fun!"
