#!/bin/bash

STEAMDIR="/home/steam/.local/share/Steam"
sudo -u steam gcloud storage cp gs://metal-ark-sample-20231207-config/island/GameUserSettings.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini"
sudo -u steam gcloud storage cp gs://metal-ark-sample-20231207-config/island/Game.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/Game.ini"
sudo systemctl start ark-island