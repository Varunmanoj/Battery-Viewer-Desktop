"""
This is a setup.py script generated by py2applet

Usage:
    python setup.py py2app
"""

from setuptools import setup

APP = ['Battery App.py']
APP_NAME = "Battery % Viewer"

DATA_FILES = ['App Icon.ico']
OPTIONS = {
    'packages': [],
    'iconfile': 'App Icon.icns',
    'plist': {
        'CFBundleName': APP_NAME,
        'CFBundleDisplayName': APP_NAME,
        'CFBundleGetInfoString': "Making Sandwiches",
        'CFBundleIdentifier': "com.metachris.osx.sandwich",
        'CFBundleVersion': "8.0",
        'CFBundleShortVersionString': "8.0",
        'NSHumanReadableCopyright': u"Copyright © 2023, Varun Manoj Kumar, All Rights Reserved"
    }

}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
