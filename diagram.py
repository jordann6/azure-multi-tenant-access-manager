from diagrams import Diagram, Cluster, Edge
from diagrams.azure.identity import ManagedIdentities, ActiveDirectory
from diagrams.azure.security import KeyVaults
from diagrams.azure.general import Resourcegroups, Subscriptions

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "Azure Multi-Tenant Access Manager",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    platform = ActiveDirectory("Platform Admins\nEntra Group\n(read-only, all tenants)")

    with Cluster("rg-mtam-dev · East US"):
        for tenant in ["alpha", "beta"]:
            with Cluster(f"Tenant: {tenant}"):
                group = ActiveDirectory(f"grp-{tenant}\nEntra Group")
                identity = ManagedIdentities(f"id-{tenant}\nManaged Identity")
                vault = KeyVaults(f"kv-{tenant}\nRBAC-authorized")

                group >> Edge(label="Secrets Officer") >> vault
                identity >> Edge(label="Secrets User\n(read-only)") >> vault
                platform >> Edge(style="dashed", label="Secrets User") >> vault
