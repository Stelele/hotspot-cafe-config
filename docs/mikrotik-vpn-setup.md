
## Step 1: Add the Ubuntu Server as a Peer on MikroTik

You'll use the public key from your Ubuntu server and its public IP address so the MikroTik knows where to call.

1. Open WinBox and go to **WireGuard** -> **Peers** tab.
2. Click the **+** (Add) icon.
3. Fill in the fields exactly like this:
* **Interface:** `wg-do` *(Based of your wiregurad interface name in the wireguard tab)*
* **Public Key:** Paste the **Ubuntu Public Key** (the one from your `publickey` file on the server).
* **Endpoint:** Type your Ubuntu server's **Public IP address**.
* **Endpoint Port:** `51820`
* **Allowed IPs:** `10.10.10.0/24`
* **Persistent Keepalive:** `00:00:25` *(Do not skip this! This forces MikroTik to ping Ubuntu every 25 seconds, keeping the Starlink NAT hole open).*


4. Click **Apply** and **OK**.

---

## Step 2: Assign the IP Address on MikroTik

Now give the MikroTik its IP address inside the VPN network.

1. Go to **IP** -> **Addresses**.
2. Click the **+** (Add) icon.
3. **Address:** `10.10.10.2/24`
4. **Network:** `10.10.10.0`
5. **Interface:** `wg-do`
6. Click **OK**.

---

## Step 3: Test the Tunnel

Once you click apply on the MikroTik, it will instantly try to connect to Ubuntu.

### 1. Check the Handshake on Ubuntu

Go back to your Ubuntu terminal and run:

```bash
sudo wg show

```

Look for a line that says **latest handshake**. If it says something like `latest handshake: 4 seconds ago`, you are officially connected!

### 2. Ping Across the Tunnel

From your Ubuntu terminal, try to ping the MikroTik:

```bash
ping 10.10.10.2

```

And from the MikroTik terminal (WinBox -> New Terminal), try to ping Ubuntu:

```routeros
/ping 10.10.10.1

```

If the pings succeed, your secure tunnel through Starlink's CGNAT is complete. Let me know if you get a handshake or if it's sitting there silently!