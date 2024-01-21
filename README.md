# ezfetch
Fetch Resmed data from ez Share WiFi SD Card (the white one)

## Basic instructions

### Tested on
* Windows 11 with Powershell Version 5.1
* ez Share SDHC + Wi-fi Adapter card (the white one)
* 32GB micro SD card

### Connect to your ez Share Card (basic/minimal instructions)

* Open your WiFi Chooser
  * You'll need at least one WiFi card on your Windows computer
  * Ideally you'll have both Wired Ethernet (for Internet) and WiFi card for ez Share Card
  * If you only have WiFi, you'll need to switch between home network & ez Share Card
* Find "ez Share"
* Click Connect (you may have to enter password - default 88888888)
* When connected to ez Share card via WiFi, click http://192.168.4.1/client?command=version
* The version information from my ez Share WiFi card is below **not all ez Share WiFi adapters will work**
   
  > LZ1801EDPG:1.0.0:2016-03-19:72 LZ1801EDRS:1.0.0:2016-03-19:72 SPEED:-H:SPEED 
  
## Installation

### Step 1 - Download ezfetch.ps1 from github

  Find a folder to store both the download powershell script and your SD Card
  data. Unzip the installation file and you should have the following contents:

  data\
  ezfetch.ps1
  readme.txt

  The default folder name for your SD Card data is 'data'.
  This can be changed by editing the powerscript file you just installed

### Step 2 - Add ezshare.card to hosts file

  Since the ezcard HTTP servers redirects you to host called 'ezshare.card'
  you will need to modify the local hosts file on your Windows computer.  This
  is the one step that will require you to be in Adminstrator mode on your PC.

* Start your favorite text editor (e.g. Notepad) in Administrator Mode
  * Click Windows -> Type Notepad
  * Right click on Notepad
  * Choose "Run as Administrator" to run in Administrator Mode
  * Start the application
* (Assuming Notepad) - Click File -> Open
* Open File: %WINDIR%\System32\drivers\etc\hosts
* Add the text below to the end of the hosts file

```
192.168.4.1    ezshare.card
```
* Save the file
* Close the editor

### Step 3 - Confirm ezshare.card hostname works

* Click Windows -> Type Powershell
* Click on Windows Powershell App (do not start as Administrator)
* Enter **_ping ezshare.card_** in powershell
* If the hostname file was edited correctly, you should see the following:

```
Pinging ezshare.card [192.168.4.1] with 32 bytes of data
```

* Note: The ping test itself will likely fail, that's OK.  You want to make sure you see this part: **ezshare.card [192.168.4.1]**

### Step 4 - Navigate to installation folder in Powershell application

* Navigate to the folder where you installed ezfetch.ps1
* In the Powershell application you started above
  * use **_dir_** command to see contents of folder and
  * use **_cd_** command to change to the correct folder
* Note: If you have OneDrive, you may need to go to OneDrive folder first

### Step 6 - Confirm you can access the card

* Enter **_ping ezshare.card_** in powershell
* This time youl should see a Reply from the card like this

```
Pinging ezshare.card [192.168.4.1] with 32 bytes of data: 
Reply from 192.168.4.1: bytes=32 time=7ms TTL=255 
Reply from 192.168.4.1: bytes=32 time=2ms TTL=255 
Reply from 192.168.4.1: bytes=32 time=2ms TTL=255 
Reply from 192.168.4.1: bytes=32 time=2ms TTL=255 
```

* If you don't see replies from the ez Share card, go back and troubleshoot

### Step 7 - Run the ezshare.ps1 script

* Enter **_ezshare.ps1_** in Powershell
* Watch as your data is downloaded (grab some coffee it will likely be slow)
* Subsequent runs will skip files already downloaded
