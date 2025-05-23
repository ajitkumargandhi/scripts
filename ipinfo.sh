#! /bin/bash
while true; do
echo "If you have list of ips in a file please Enter file name"
echo "or press Enter to go to Enter ip."
read -p "Enter file name:" file
if [ $file ]
then
  while IFS= read ip
  do
   echo "$ip"
   #curl ipinfo.io/$ip
   curl ipinfo.io/$ip?token=$TOKEN
   #curl ipinfo.io/ranges/$ip?token=$TOKEN
  done < "$file"
else 
  read -p "Enter ip:" ip
  curl ipinfo.io/$ip?token=$TOKEN
   echo -e "\n\n To quite script prace Q or q else press Enter to restart the script"
  # Add this line to check for key press and exit the program
  read -n 1 key
  if [[ $key == 'q' || $key == 'Q' ]]; then
    exit 0
  fi
fi
