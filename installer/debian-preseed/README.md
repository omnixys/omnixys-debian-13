# debian-preseed backend

Production backend for Debian 13 unattended installation using preseed.

The renderer generates an early identity script using the native cdebconf
frontend and a separate late network script. Static network values are written
directly into the target filesystem and validated before installation finishes;
four empty network values preserve DHCP.

Implemented API:

- validate
- render
- build
- verify
- package
