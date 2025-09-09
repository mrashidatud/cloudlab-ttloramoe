# -*- coding: utf-8 -*-
# Single-node r7525 GPU profile with large /local blockstore

import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

pc = portal.Context()
request = pg.Request()

pc.defineParameter("nodeType", "Hardware Type",
                   portal.ParameterType.STRING, "r7525")
pc.defineParameter("diskImage", "Disk Image",
                   portal.ParameterType.STRING,
                   "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD")
pc.defineParameter("localFSGiB",
                   "Size of node-local dataset at /local (ephemeral; best-effort)",
                   portal.ParameterType.INTEGER, 1024)
pc.defineParameter("datasetName",
                   "Blockstore (dataset) name used by CloudLab snapshot UI",
                   portal.ParameterType.STRING, "bs")

params = pc.bindParameters()

node = request.RawPC("gpu-node")
node.hardware_type = params.nodeType
node.disk_image = params.diskImage

# ---- Node-local dataset (ephemeral blockstore) per CloudLab docs ----
# Using the doc pattern: bs = node.Blockstore("<NAME>", "<MOUNTPOINT>"); bs.size="NNNGB"
# This makes an LVM-backed local filesystem that is created and mounted automatically. :contentReference[oaicite:1]{index=1}
if int(params.localFSGiB) > 0:
    bs = node.Blockstore(str(params.datasetName), "/local")
    bs.size = str(int(params.localFSGiB)) + "GB"
    # Let the mapper allocate as much as possible up to the requested size.
    try:
        bs.best_effort = True
    except Exception:
        pass
    # No placement hint needed for the node-local dataset example; CL will stripe across

# Run stage 1 at boot (installs NVIDIA driver and reboots)
node.addService(pg.Execute(
    shell="bash",
    command=("sudo -H bash -lc '"
             "for i in $(seq 1 60); do "
             "  [ -f /local/repository/scripts/setup-stage1-nvidia.sh ] && break; "
             "  sleep 5; "
             "done; "
             "chmod +x /local/repository/scripts/*.sh || true; "
             "/local/repository/scripts/setup-stage1-nvidia.sh'")))

pc.printRequestRSpec(request)
 # type: ignore