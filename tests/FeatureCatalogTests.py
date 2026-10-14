#!/usr/bin/env python3
"""Guard protocol/version distinctions and fail-closed generated descriptors."""
import importlib.util, json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class FeatureCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=json.loads((ROOT/'docs/feature-catalog.json').read_text())
        cls.descriptors=json.loads((ROOT/'docs/control-descriptors.json').read_text())
    def enum(self,proto,name,symbol):
        p=next(p for p in self.catalog['protocols'] if p['id']==proto)
        return next(e['value'] for e in p['enums'][name]['entries'] if e['symbol']==symbol)
    def test_byte_code_not_java_ordinal(self):
        self.assertEqual(self.enum('v2t1','NcAsmInquiredType','MODE_NC_ASM_AUTO_NC_MODE_SWITCH_AND_ASM_SEAMLESS'),0x15)
        self.assertEqual(self.enum('v2t1','NcAsmInquiredType','MODE_NC_ASM_DUAL_NC_MODE_SWITCH_AND_ASM_SEAMLESS'),0x17)
    def test_support_function_not_inquiry(self):
        f=next(f for f in self.catalog['support_functions'] if f['protocol']=='v2t1' and f['symbol']=='MODE_NC_ASM_NOISE_CANCELLING_DUAL_AUTO_AMBIENT_SOUND_MODE_LEVEL_ADJUSTMENT')
        self.assertEqual(f['value'],0x68)
        self.assertNotEqual(f['value'],self.enum('v2t1','NcAsmInquiredType','MODE_NC_ASM_AUTO_NC_MODE_SWITCH_AND_ASM_SEAMLESS'))
    def test_family_table_and_source_identity(self):
        self.assertEqual({p['id'] for p in self.catalog['protocols']},{'v1t1','v1t2','v2t1','v2t2'})
        for p in self.catalog['protocols']:
            self.assertEqual(p['frame_type'],12 if p['id'].endswith('t1') else 14)
        self.assertEqual(self.catalog['reference']['commit'],'f11d686332e9aaf7630f9fb8a104b70c5d6f342c')
    def test_updater_excluded_in_both_families(self):
        rows=[c for c in self.catalog['controls'] if c['subsystem'] in ('Updt','Update')]
        self.assertTrue(rows)
        self.assertTrue(all(c['category']=='firmware_updater_excluded' for c in rows))
    def test_no_catalogue_writer_is_automatically_enabled(self):
        self.assertGreater(len(self.descriptors['controls']),100)
        for d in self.descriptors['controls']:
            self.assertFalse(d['enabled'])
            self.assertTrue(d['reason'])
            self.assertIn(d['frame_type'],[12,14])
    def test_shared_wire_onoff_inversion(self):
        enums=self.catalog['shared_enums']['v2']['OnOffSettingValue']['entries']
        self.assertEqual(next(e['value'] for e in enums if e['symbol']=='ON'),0)
        self.assertEqual(next(e['value'] for e in enums if e['symbol']=='OFF'),1)
        for d in self.descriptors['controls']:
            for field in d['fields']:
                if d['protocol'].startswith('v2') and field['reference_default'] and 'OnOffSettingValue::' in field['reference_default']:
                    values={x['label']:x['value'] for x in field['options']}
                    self.assertEqual(values.get('On'),0)
                    self.assertEqual(values.get('Off'),1)
    def test_public_outputs_contain_no_local_private_identifiers(self):
        text=json.dumps(self.catalog)+json.dumps(self.descriptors)
        self.assertNotIn('/Users/',text)
        self.assertNotIn('ac-80-',text)
        self.assertNotIn('extracted/Payload',text)
    def test_generated_catalogue_matches_source_when_available(self):
        reference=ROOT/'tests/reference/SonyHeadphonesClient/libmdr/include/mdr'
        script=ROOT/'scripts/generate-feature-catalog.py'
        if not reference.exists() or not script.exists():
            self.skipTest('Optional pinned-source regeneration check; public builds need no reference checkout')
        spec=importlib.util.spec_from_file_location('feature_catalog',script)
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        regenerated=module.generate(reference=reference,anchors_path=ROOT/'docs/ipa-protocol-provenance.json')
        self.assertEqual(json.loads(json.dumps(regenerated)),self.catalog)
        self.assertEqual(module.control_descriptors(regenerated),self.descriptors)

if __name__=='__main__':unittest.main()
