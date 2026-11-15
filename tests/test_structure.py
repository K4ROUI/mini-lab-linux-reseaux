"""Tests statiques : ne requièrent ni sudo ni namespaces réseau."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAB = (ROOT / "scripts/lab.sh").read_text(encoding="utf-8")
FIREWALL = (ROOT / "scripts/firewall.sh").read_text(encoding="utf-8")
DNS = (ROOT / "config/dnsmasq.conf").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")


class LabStaticChecks(unittest.TestCase):
    def test_expected_structure(self):
        for rel in ("www/health.txt", "scripts/lab.sh", "scripts/firewall.sh",
                    "config/dnsmasq.conf", "docs/architecture.md", "docs/diagnostic.md",
                    "docs/validation.md", ".github/workflows/lab.yml"):
            with self.subTest(path=rel):
                self.assertTrue((ROOT / rel).is_file())

    def test_three_distinct_namespaces(self):
        for name in ("irs-lab-client", "irs-lab-router", "irs-lab-server"):
            self.assertIn(name, LAB)
        self.assertIn('ip netns add "$ns"', LAB)

    def test_static_ip_addresses(self):
        for ip in ("10.70.10.10", "10.70.10.1", "10.70.20.1", "10.70.20.10"):
            with self.subTest(address=ip):
                self.assertIn(ip, LAB)

    def test_explicit_routes_and_forwarding(self):
        self.assertIn('route add 10.70.20.0/24 via', LAB)
        self.assertIn('route add 10.70.10.0/24 via', LAB)
        self.assertIn('net.ipv4.ip_forward=1', LAB)

    def test_dns_records_point_to_the_server(self):
        self.assertIn('listen-address=10.70.20.10', DNS)
        self.assertIn('address=/service.lab.test/10.70.20.10', DNS)
        self.assertIn('no-resolv', DNS)

    def test_firewall_default_drop_and_allowed_ports(self):
        self.assertRegex(FIREWALL, r'iptables -P FORWARD DROP')
        for port in (53, 8080):
            self.assertIn(f'--dport {port}', FIREWALL)
        self.assertNotIn('--dport 9090 -j ACCEPT', FIREWALL)

    def test_server_has_a_health_endpoint(self):
        self.assertEqual((ROOT / "www/health.txt").read_text(encoding="utf-8").strip(),
                         "OK - laboratoire Linux et reseaux")
        self.assertIn('python3 -m http.server 8080', LAB)

    def test_positive_and_negative_integration_checks(self):
        self.assertIn('curl --silent --show-error --fail', LAB)
        self.assertIn('le port 9090 aurait dû être bloqué', LAB)
        self.assertIn('iptables -S FORWARD', LAB)

    def test_readme_explains_kernel_namespace_not_a_vm(self):
        self.assertIn('network namespaces', README)
        self.assertIn('pas trois ordinateurs', README)
        self.assertIn('validation réseau de bout en bout', README)


if __name__ == "__main__":
    unittest.main()
