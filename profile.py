# Single-node d8545 (HGX A100) profile with flexible /local blockstore (Python 2 safe)

import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

pc = portal.Context()
request = pg.Request()

pc.defineParameter("nodeType", "Hardware Type",
                   portal.ParameterType.STRING, "d8545")
pc.defineParameter("diskImage", "Disk Image",
                   portal.ParameterType.STRING,
                   "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD")

# Ask for a large /local on the d8545 (1.6 TB NVMe exists; 1400 GiB is a safe default).
pc.defineParameter("localFSGiB",
                   "Size of /local (ephemeral blockstore, GiB; best-effort)",
                   portal.ParameterType.INTEGER, 1400)

# Placement hint: "any" is most portable; "nonsysvol" prefers non-system disk if advertised.
pc.defineParameter("localFSPlacement",
                   "Blockstore placement hint (any or nonsysvol)",
                   portal.ParameterType.STRING, "any")

params = pc.bindParameters()

node = request.RawPC("gpu-node")
node.hardware_type = params.nodeType
node.disk_image = params.diskImage

# Ephemeral storage at /local
if int(params.localFSGiB) > 0:
    bs = node.Blockstore("node-local", "/local")
    bs.size = str(int(params.localFSGiB)) + "GB"
    try:
        bs.best_effort = True
    except Exception:
        pass
    placement = str(params.localFSPlacement).strip().lower()
    if placement in ["any", "nonsysvol"]:
        bs.placement = placement

# Bootstrap stage 1 (NVIDIA driver; will reboot once). Stage 2 resumes via systemd.
node.addService(pg.Execute(
    shell="bash",
    command="sudo -H /local/repository/scripts/setup-stage1-nvidia.sh"
))

pc.printRequestRSpec(request)
 # type: ignore