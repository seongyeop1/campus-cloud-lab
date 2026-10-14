import importlib.machinery
import importlib.util
import json
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

LAB_DIR = Path(__file__).resolve().parent.parent
_loader = importlib.machinery.SourceFileLoader("labctl", str(LAB_DIR / "labctl"))
_spec = importlib.util.spec_from_loader("labctl", _loader)
labctl = importlib.util.module_from_spec(_spec)
_loader.exec_module(labctl)


def fake_hasher(pw):
    return "$2a$14$fakehash" + str(len(pw))


class LabTestCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.paths = labctl.Paths(self._tmp.name)

    def init(self, n=3):
        return labctl.cmd_init(self.paths, n, hasher=fake_hasher)


class PasswordTest(unittest.TestCase):
    def test_length_and_alphabet(self):
        pw = labctl.generate_password()
        self.assertEqual(len(pw), labctl.PASSWORD_LENGTH)
        self.assertTrue(set(pw) <= set(labctl.PASSWORD_ALPHABET))

    def test_not_repeated(self):
        self.assertEqual(len({labctl.generate_password() for _ in range(200)}), 200)


class InitTest(LabTestCase):
    def test_ids_and_files(self):
        self.assertEqual(self.init(3), ["s01", "s02", "s03"])
        rows = self.paths.roster.read_text().splitlines()
        self.assertEqual(rows[0], "id,password")
        self.assertEqual(len(rows), 4)
        self.assertEqual(sorted(json.loads(self.paths.hashes.read_text())), ["s01", "s02", "s03"])

    def test_plaintext_only_in_roster(self):
        self.init(2)
        pws = [r.split(",")[1] for r in self.paths.roster.read_text().splitlines()[1:]]
        self.assertNotIn(pws[0], self.paths.hashes.read_text())

    def test_permissions(self):
        self.init(1)
        self.assertEqual(stat.S_IMODE(self.paths.roster.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.paths.secrets.stat().st_mode), 0o700)

    def test_refuses_overwrite(self):
        self.init(1)
        with self.assertRaises(labctl.LabError):
            self.init(1)
        labctl.cmd_init(self.paths, 2, force=True, hasher=fake_hasher)

    def test_bounds(self):
        for n in (0, labctl.MAX_STUDENTS + 1):
            with self.assertRaises(labctl.LabError):
                self.init(n)


class RenderTest(LabTestCase):
    def render(self, mode, **kw):
        self.init(2)
        labctl.cmd_render(self.paths, mode, **kw)
        return self.paths.compose.read_text(), self.paths.caddyfile.read_text()

    def test_requires_init(self):
        with self.assertRaises(labctl.LabError):
            labctl.cmd_render(self.paths, "local")

    def test_local_compose(self):
        compose, _ = self.render("local")
        self.assertIn('"127.0.0.1:8080:8080"', compose)
        for sid in ("s01", "s02"):
            self.assertIn(f"  {sid}:", compose)
            self.assertIn(f"net-{sid}", compose)
        self.assertEqual(compose.count("mem_limit: 512m"), 2)
        self.assertEqual(compose.count('cpus: "0.5"'), 2)
        self.assertEqual(compose.count("pids_limit: 256"), 2)

    def test_students_have_no_ports_and_no_dangerous_options(self):
        compose, _ = self.render("local")
        student_part = compose.split("  s01:")[1].split("networks:\n  net-s01")[0]
        for bad in ("ports:", "privileged", "docker.sock", "network_mode", "pid: host"):
            self.assertNotIn(bad, student_part)
        self.assertNotIn("privileged", compose)
        self.assertNotIn("docker.sock", compose)

    def test_each_student_has_own_network_and_proxy_joins_all(self):
        compose, _ = self.render("local")
        proxy = compose.split("  proxy:")[1].split("  s01:")[0]
        self.assertIn("- net-s01", proxy)
        self.assertIn("- net-s02", proxy)
        s01 = compose.split("  s01:")[1].split("  s02:")[0]
        self.assertNotIn("net-s02", s01)

    def test_local_caddyfile(self):
        _, caddy = self.render("local")
        self.assertIn(":8080 {", caddy)
        self.assertIn("auto_https off", caddy)
        self.assertIn("reverse_proxy s01:7681", caddy)
        self.assertIn("s01 $2a$14$fakehash16", caddy)
        self.assertNotIn("tls internal", caddy)

    def test_deploy_requires_domain(self):
        self.init(1)
        with self.assertRaises(labctl.LabError):
            labctl.cmd_render(self.paths, "deploy")
        with self.assertRaises(labctl.LabError):
            labctl.cmd_render(self.paths, "deploy", domain="bad domain{")

    def test_deploy(self):
        compose, caddy = self.render("deploy", domain="lab.example.ac.kr")
        self.assertIn('"80:80"', compose)
        self.assertIn('"443:443"', compose)
        self.assertNotIn("8080", compose)
        self.assertTrue(caddy.startswith("lab.example.ac.kr {"))
        self.assertNotIn("tls internal", caddy)
        self.assertNotIn("auto_https off", caddy)

    def test_deploy_tls_internal(self):
        _, caddy = self.render("deploy", domain="1.2.3.4.sslip.io", tls_internal=True)
        self.assertIn("tls internal", caddy)


class ResetTest(LabTestCase):
    def test_commands(self):
        self.init(2)
        labctl.cmd_render(self.paths, "local")
        calls = []
        steps = labctl.cmd_reset(self.paths, "s02", run=lambda cmd, check: calls.append(cmd))
        self.assertEqual(steps, calls)
        self.assertIn("campus-lab-home-s02", calls[1])
        self.assertEqual(calls[2][-3:], ["up", "-d", "s02"])
        self.assertEqual(calls[2][-1], "s02")
        self.assertFalse(any("s01" in c for cmd in calls for c in cmd))

    def test_invalid_id(self):
        self.init(1)
        labctl.cmd_render(self.paths, "local")
        for bad in ("s1", "../x", "s01; rm", "s09"):
            with self.assertRaises(labctl.LabError):
                labctl.cmd_reset(self.paths, bad, run=lambda *a, **k: None)

    def test_command_failure_is_reported(self):
        self.init(1)
        labctl.cmd_render(self.paths, "local")

        def boom(cmd, check):
            raise subprocess.CalledProcessError(1, cmd)

        with self.assertRaises(labctl.LabError):
            labctl.cmd_reset(self.paths, "s01", run=boom)


if __name__ == "__main__":
    unittest.main()
