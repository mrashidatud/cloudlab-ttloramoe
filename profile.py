#
# Single-node r7525 GPU profile + MAX local storage at /local
#
import geni.portal as portal
import geni.rspec.pg as pg
import geni.rspec.emulab as emulab

pc = portal.Context()
rspec = pg.Request()

pc.defineParameter("nodeType", "Hardware Type",
                   portal.ParameterType.STRING, "r7525")
pc.defineParameter("diskImage", "Disk Image",
                   portal.ParameterType.STRING,
                   "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD")
# How much of the node-local disk to carve out for an ephemeral FS at /local.
# r7525 has a 2TB HDD; 1800–1900 is usually safe. Increase/decrease as needed.
pc.defineParameter("localFSGiB", "Size of /local (ephemeral blockstore, GiB)",
                   portal.ParameterType.INTEGER, 1500)

params = pc.bindParameters()

node = rspec.RawPC("gpu-node")
node.hardware_type = params.nodeType
node.disk_image = params.diskImage

# Ephemeral blockstore mounted at /local (use non-system volume if available)
bs = node.Blockstore("node-local", "/local")
bs.size = f"{int(params.localFSGiB)}GB"
bs.placement = "nonsysvol"
node.addBlockstore(bs)

# Clone repo into /local (CloudLab also clones into /local/repository automatically),
# then start stage 1 (NVIDIA, reboot) which enables stage 2 via systemd.
node.addService(pg.Execute(
    shell="bash",
    command="sudo -H /local/repository/scripts/setup-stage1-nvidia.sh"
))

pc.printRequestRSpec(rspec)
