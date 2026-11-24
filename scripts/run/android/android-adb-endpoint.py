# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Validate the frozen local ADB endpoint in owned emulator requests."""


def validate(value):
    if (not isinstance(value, dict) or set(value) != {'schema_version', 'host', 'port', 'socket'} or
            type(value.get('schema_version')) is not int or value['schema_version'] != 1 or value.get('host') != 'localhost' or
            type(value.get('port')) is not int or not 1 <= value['port'] <= 65535 or
            value.get('socket') != 'tcp:localhost:' + str(value['port'])):
        raise ValueError('Invalid frozen Android ADB endpoint')
    return value


def environment(value):
    value = validate(value)
    return {'ADB_SERVER_SOCKET': value['socket'], 'ANDROID_ADB_SERVER_ADDRESS': value['host'],
            'ANDROID_ADB_SERVER_PORT': str(value['port'])}
