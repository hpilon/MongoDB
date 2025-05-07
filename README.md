# 📌 MongoDB - create_mongodb_container_v5.1.sh script

![mongodb overview](overview-MongoDB.drawio.svg)

✅ Information:

This script was tested on ubuntu 22.04 and Red Hat 8.10 systems only. 

The script **"create_mongodb_container_v5.1.sh"** includes the use of:
    
- Percona Open Source MongoDB  https://www.percona.com/mongodb/software/mongodb-distribution instead of the default MongoDB CE

- Percona Monitoring and Management

- Percona Backup for MongoDB

 - In addition:

   - Added some logic to run this script in a CI/CD pipeline 

   - Optimized a few areas of the script, and cleaned the bash syntax 

    - Added support for both logical and physical Percona (bpm) backup & restore 

<b style="color:red">
⚠️ Warning Disclaimer 

- The outcome of this script is NOT supported by MongoDB Inc or by Percona under any of their commercial support
subscriptions or otherwise</b>

⚠️ Dependency
 
 - The script utilize "percona-release_latest.jammy_all.deb" Debain software package as part of the container build phase.

```
PERCONA_SOFTWARE="percona-release_latest.jammy_all.deb" # key software package from Percona required to build the Docker image
```

**So it is imperative the above Debian distribution be available locally prior to invoking the script.**     

## Comparison if MongoDB CE vs Percona MongoDB (PSMDB)


✅ Additional Information:

# 📊 MongoDB Products Comparison (in case there is some interest)

| Feature / Product | MongoDB Community (CE) | MongoDB Enterprise | Percona Server for MongoDB (PSMDB) | Percona MongoDB Professional (Prof) |
|:------------------|:----------------------|:-------------------|:----------------------------------|:------------------------------------|
| License           | Server Side Public License (SSPL) | Commercial License | Open Source (SSPL + Percona modifications) | Commercial Support Package |
| Cost              | Free                   | Paid Subscription   | Free                              | Paid Support Plan                  |
| Support           | Community support only | Official MongoDB Inc. support | Community support + optional paid Percona support | Full Percona enterprise support |
| Security Features | Basic (Authentication, TLS) | Advanced (LDAP, Kerberos, Encryption at Rest) | Advanced (LDAP, Encryption at Rest, Audit Logs, KMIP) | Same as PSMDB + tuning, hardening |
| Backup Tools      | mongodump/mongorestore | Ops Manager + Cloud Manager Backups | Percona Backup for MongoDB (PBM) | PBM + Full Backup/Recovery support |
| Monitoring        | Basic (manual tools)    | Advanced via Ops Manager / Cloud Manager | Percona Monitoring and Management (PMM, Free) | Full Monitoring + tuning |
| Sharding & Replication | Yes               | Yes                 | Yes                              | Yes                                |
| Enterprise Integrations | No                | Yes (LDAP, Kerberos, SNMP, etc.) | Yes (LDAP, Kerberos, KMIP) | Yes                               |
| Hot Backups       | No                     | Yes                 | Yes (via PBM and hot backup) | Yes                                |
| Performance Enhancements | No              | Some                | Some (better memory tuning, RocksDB optional) | Yes (custom tuning support) |
| Encryption at Rest | Only via filesystem tools | Built-in          | Built-in                         | Built-in + Enterprise hardening     |
| Cloud Services Integration | No            | Yes (Atlas)         | No (self-host only)            | No (self-host only)                      |
| Management Tools  | Manual or Community Tools | Ops Manager, Cloud Manager | PMM (Free)         | PMM + Expert Analysis               |

---

# 🧐 **Summary:**

| Product | Best For |
|:--------|:---------|
| MongoDB CE | Developers, small teams, self-managed deployments |
| MongoDB Enterprise | Large companies needing integrated tools and official MongoDB Inc. support |
| Percona Server for MongoDB | Advanced users wanting free enterprise features and open-source tools |
| Percona MongoDB Prof | Companies needing professional 24/7 support and proactive database management |

---

# 📌 Important Note:
- **Percona Server for MongoDB (PSMDB)** is MongoDB with **enterprise-grade features for free**.

- **Percona MongoDB Professional** is **professional services and support** on top of PSMDB or MongoDB CE/Enterprise.

---

✅ Information:

- By default bot the Percona PMM and PBM software are installed within the Docker image but not configure or started.

✅ The script "control_pmm_pbm-clients-to-containers_v1.sh" maybe of interest to facilitate the above. 

💡 Have fun, and feel free to modify these scripts to your liking. 
