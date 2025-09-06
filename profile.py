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
pc.defineParameter("localFSGiB", "Size of /local (ephemeral blockstore, GiB)",
                   portal.ParameterType.INTEGER, 1900)

params = pc.bindParameters()

node = request.RawPC("gpu-node")
node.hardware_type = params.nodeType
node.disk_image = params.diskImage

# Ephemeral node-local storage mounted at /local
bs = node.Blockstore("node-local", "/local")
bs.size = str(int(params.localFSGiB)) + "GB"   # Python 2 compatible
bs.placement = "nonsysvol"

# Run stage 1 at boot (installs NVIDIA driver and reboots)
node.addService(pg.Execute(
    shell="bash",
    command="sudo -H /local/repository/scripts/setup-stage1-nvidia.sh"
))

pc.printRequestRSpec(request)
 # type: ignore