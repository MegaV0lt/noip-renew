#!/bin/bash
set -e

PYTHON=python3
USER="$(whoami)"
if [[ "$USER" == 'root' ]] ; then
  USER="$1"
  if [[ -z "$USER" ]] ; then
    echo "Chrome is safer to run as normal user instead of 'root', so"
    echo "run the script as a normal user (with sudo permission), "
    echo "or specify the user: $0 <user>"
    exit 1
  fi
  HOME="/home/${USER}"
else
  SUDO='sudo'
fi

f_config() {
  LOGDIR="/var/log/noip-renew/${USER}"
  INSTDIR='/usr/local/bin'
  INSTEXE="${INSTDIR}/noip-renew-${USER}.sh"
  CRONJOB="0 1  * * *  $INSTEXE $LOGDIR"  #Debian
}

f_install() {
  OS="$(hostnamectl | grep -i 'operating system')"
  echo "Operating System: $OS"
  case "$OS" in
    *Arch?Linux*) f_install_arch ;;
    *)            f_install_debian ;;
  esac
  # Debian9 package 'python-selenium' does not work with chromedriver,
  # Install from pip, which is newer
  $SUDO $PYTHON -m pip install selenium
}

f_install_arch(){
  $SUDO pacman -Qi cronie > /dev/null ||  $SUDO pacman -S cronie
  $SUDO pacman -Qi python > /dev/null ||  $SUDO pacman -S python
  $SUDO pacman -Qi python-pip > /dev/null ||  $SUDO pacman -S python-pip
  $SUDO pacman -Qi chromium > /dev/null || $SUDO pacman -S chromium
}

f_install_debian(){
  echo "Installing necessary packages..."
    read -r -p 'Perform apt-get update? (y/n): ' update
      if [[ "${update^^}" == 'Y' ]] ; then
        $SUDO apt-get update
      fi

      $SUDO apt -y install chromium-chromedriver \
        || $SUDO apt -y install chromium-driver \
        || $SUDO apt -y install chromedriver

      $SUDO apt -y install cron 

      PYV="$(python3 -c "import sys;t='{v[0]}{v[1]}'.format(v=list(sys.version_info[:2]));sys.stdout.write(t)";)"
      if [[ "$PYV" -lt "36" ]] || ! hash python3 ; then
        echo 'This script requires Python version 3.6 or higher. Attempting to install...'
        $SUDO apt-get -y install python3
      fi
 
      # Update Chromium Browser or script won't work. In debian chromium instead chromium-browser is needed.
      $SUDO apt -y install chromium-browser \
        || $SUDO apt -y install chromium
      $SUDO apt -y install $PYTHON-pip
}

f_deploy() {
  echo 'Deploying the script...'

  # Remove current installation first.
  if ls $INSTDIR/*noip-renew* &>/dev/null ; then
    $SUDO rm "${INSTDIR}/*noip-renew*"
  fi

  $SUDO mkdir -p "$LOGDIR"
  $SUDO chown "$USER" "$LOGDIR"
  $SUDO cp noip-renew.py "$INSTDIR"
  $SUDO cp noip-renew-skd.sh "$INSTDIR"
  $SUDO cp noip-renew.sh "$INSTEXE"
  $SUDO chown "$USER" "$INSTEXE"
  $SUDO chown "$USER" "${INSTDIR}/noip-renew-skd.sh"
  $SUDO chmod 700 "$INSTEXE"
  f_noip
  $SUDO crontab -u "$USER" -l | grep -v '/noip-renew' | $SUDO crontab -u "$USER" -
  ($SUDO crontab -u "$USER" -l; echo "$CRONJOB") | $SUDO crontab -u "$USER" -
  $SUDO sed -i 's/USER=/USER='"$USER"'/1' "${INSTDIR}/noip-renew-skd.sh"
  echo 'Installation Complete.'
  echo 'To change noip.com account details, please run setup.sh again.'
  echo "Logs can be found in '$LOGDIR'"
}

f_noip() {
  echo 'nter your No-IP Account details...'
  read -r -p 'Username: ' uservar
  read -r -sp 'Password: ' passvar

  passvar="$(echo -n "$passvar" | base64)"
  echo

  $SUDO sed -i 's/USERNAME=".*"/USERNAME="'"$uservar"'"/1' "$INSTEXE"
  $SUDO sed -i 's/PASSWORD=".*"/PASSWORD="'"$passvar"'"/1' "$INSTEXE"
}

f_installer() {
  f_config
  f_install
  f_deploy
}

f_uninstall() {
  $SUDO sed -i '/noip-renew/d' /etc/crontab
  $SUDO rm "${INSTDIR}/*noip-renew*"
  read -r -p 'Do you want to remove all log files? (y/n): ' clearLogs
  if [[ "${clearLogs^^}" == 'Y' ]] ; then
    $SUDO rm -rf "$LOGDIR"
  fi
}

PS3='Select an option: '
options=('Install/Repair Script' 'Update noip.com account details' 'Uninstall Script' 'Exit setup.sh')
echo 'No-IP Auto Renewal Script Setup.'
select opt in "${options[@]}" ; do
  case $opt in
    'Install/Repair Script')
      f_installer
      break
      ;;
    'Update noip.com account details')
      f_config
      f_noip
      echo 'noip.com account settings updated.'
      break
      ;;
    'Uninstall Script')
      f_config
      if ls "$INSTDIR"/*noip-renew* &>/dev/null ; then
        f_uninstall
        echo 'Script successfully uninstalled.'
      else
        echo 'Script is not installed.'
      fi
      break
      ;;
    'Exit setup.sh')
      break
      ;;
    *) echo "Invalid option $REPLY" ;;
  esac
done
