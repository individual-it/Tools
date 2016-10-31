# Tools
Collection of different scripts

## Add-PrintersOfRDClientToRDHost.ps1
We could not manage to map the printers of a RDP client to the RDP server, so we wrote this script to fix the problem. You have to share all printers on the client that you like to see on the server. The script will find the name of the RDP client, map all shared printers to the server, find the default printer of the client and set the coresponding printer as default on the server. 
