# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)
# watashi v12.3.40dev: the key is matched without its comment. The line that
# add_remote_assistant.sh once wrote ends in the old project's name, so the
# renamed comment no longer matched it and the key would have stayed; the key
# itself is what has to go, whatever its comment says.
watashi_ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWEXarp7YrTNX+4uNfdYtQ1lVsrD9/6oHaNiR6kgzoeShD/+3Ljou3veXofVstCb6CpFZdmOaKXNJyT5N+gm0eXwYJNsnrkCRq9h/6ydkoVdPAINzHZoetVqwqAPgmqzR8xTKZPP/Ky3Ks8OQEIg1Swnm9XXuP+ApmvOxGut9pPhOozKSATklojRaAmhdz4y9YpkLi94C1Ixd10Ewjld4pnVp4+uDTkXV2i3N3lH5x6zFrk2tefigoZ60brNWC3TGL3SjQ4obkD2qKpKqIRy63cUzfI0lP/0vZ7Ms5ESPlLI/ebMGvns9hINi1KRJ8m0//Jy0CDngJNJxG8KGbvqvLu/avmdVUHr48y7bk6VTGicMp16LfbszRQRF2d61n5uwBGXUB5DbVNI00yOdqAflDEloBEchqiWIEotBXyGTB1e2V1Oe95W27h9QSMbhNwmEk/QGPn4yhRgTbFq1TwNhE6DXZrCUbW8x4KVMQTSD+seUB0fMgTTXtzpPEo3mFAME="

if [ ! -f ~/.ssh/authorized_keys ]; then
    echo "remote assistant access is removed!"
    exit 0
fi
grep -v -F "$watashi_ssh_key" ~/.ssh/authorized_keys >~/.ssh/authorized_keys_temp
mv ~/.ssh/authorized_keys_temp ~/.ssh/authorized_keys

echo "remote assistant access is removed!"
