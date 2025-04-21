# Firewalla Blue Plus Network Setup

## **Network Setup Diagram**
```
ISP ---> HomeHub 3000 (Bridge Mode, LAN Port 1)
       ---> TP-Link Archer A6 (LAN Port, Access Point Mode)
             A6 LAN Port 2 ---> TP-Link SG108 Switch (LAN Port 1)
                         Switch LAN Port 2 ---> Firewalla Blue Plus (Single Ethernet Port connected to Switch)
                         Switch LAN Ports 3+ ---> Wired Devices
Wi-Fi Devices ---> Archer A6 ---> SG108 Switch ---> Firewalla Blue Plus
```

---

## **Step-by-Step Configuration**

### **1. HomeHub 3000 in Bridge Mode**
- The **HomeHub 3000** is configured in **bridge mode** to pass the public IP address from your ISP.
- **Connection**: Use **LAN Port 1 on the HomeHub** to connect to **LAN Port 1 on the Archer A6**.

---

### **2. TP-Link Archer A6 in Access Point Mode**
- Configure the **Archer A6** in **Access Point Mode**:
  - Disable its router functionality (no NAT or DHCP).
  - The Archer A6 will only provide Wi-Fi access and forward all traffic to the Firewalla.
- **Connections**:
  - **LAN Port 1** on the Archer A6 connects to **LAN Port 1 on the HomeHub 3000**.
  - **LAN Port 2** on the Archer A6 connects to **LAN Port 1 on the TP-Link SG108 Switch**.

---

### **3. TP-Link SG108 Switch**
- The switch acts as the central hub for your network, distributing the connection to all devices.
- **Connections**:
  - **LAN Port 1**: Connects to **LAN Port 2 on the Archer A6**.
  - **LAN Port 2**: Connects to the **Firewalla Blue Plus**.
  - **LAN Ports 3+**: Connect to wired devices like PCs, consoles, or printers.

---

### **4. Firewalla Blue Plus in DHCP Mode**
- The **Firewalla Blue Plus** is configured as the **primary router**:
  - Assigns IP addresses to all devices on the network.
  - Routes traffic between the internet and internal devices.
  - Monitors traffic for both wired and wireless devices.
- **Connection**: Connect the **Firewalla Blue Plus** to **LAN Port 2 on the SG108 Switch**.

---

### **5. Wired and Wireless Devices**
- **Wired Devices**:
  - Connect directly to the available ports on the switch (LAN Ports 3+).
- **Wi-Fi Devices**:
  - Connect to the **Archer A6’s Wi-Fi network**.
  - Traffic from Wi-Fi devices is forwarded to the Firewalla for routing and monitoring.

---

## **Key Notes**
1. **No WAN Ports Are Used**:
   - The Archer A6 operates in Access Point Mode, so its WAN port is unused.
   - The HomeHub connects to the Archer A6 via a LAN port.

2. **Firewalla as the Router**:
   - The Firewalla is the single point of routing and DHCP for the entire network.

3. **All Traffic is Routed Through the Firewalla**:
   - Both wired and Wi-Fi traffic pass through the Firewalla for monitoring and control.

4. **No Double NAT**:
   - Placing the Archer A6 in Access Point Mode ensures there is no conflict with the Firewalla's router functionality.

---

## **Troubleshooting Tips**
- If devices aren’t receiving IP addresses:
  - Ensure the Firewalla is in **DHCP Mode**.
  - Confirm the Archer A6’s DHCP is disabled.
- If Wi-Fi devices aren’t visible in the Firewalla app:
  - Verify that the Archer A6 is correctly connected to the switch via its LAN port.
- For networks faster than 500 Mbps:
  - Consider upgrading to the **Firewalla Gold**, which supports gigabit speeds.