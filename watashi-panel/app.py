#!/opt/watashi-manager/.venv313/bin/python
# watashi v12.3.40dev: the old project name was taken out of this file (names, paths and links only)

if __name__ == "__main__":
    import bjoern
    import watashipanel
    bjoern.run(wsgi_app=watashipanel.create_app(), host="127.0.0.1", port=9000)
