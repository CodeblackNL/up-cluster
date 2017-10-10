# up-cluster
Scripts &amp; provisioning files for building an UP cluster.

# Getting Started
## Download required files
Follow the instructions in each Download.md, listed in \Download.md.

## Create the windows images
### New-UpWindowsImage -Edition Core
Creates a windows image using the Core edition of windows.
Includes the UP drivers, windows updates & provisioning files.

### New-UpWindowsImage -Edition GUI
Creates a windows image using the GUI edition of windows.
Includes the UP drivers, windows updates & provisioning files.

### New-UpWindowsImage -Edition GUI -NoFiles
Creates a windows image using the GUI edition of windows.
Includes the UP drivers & windows updates, but no provisioning files.
This image is intended for the configuration-node, running WDS & DSC.
