#!/usr/bin/env python3
"""Reproducible public protocol inventory; never infer a writer from a class name.

Source declarations come from a pinned MIT reference; optional compact IPA anchors
add provenance. Packet layouts remain reference-declared unless individually audited.
"""
import argparse, hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMIT = 'f11d686332e9aaf7630f9fb8a104b70c5d6f342c'
REFERENCE = ROOT / 'tests/reference/SonyHeadphonesClient/libmdr/include/mdr'
SCHEMAS = ('V1T1', 'V1T2', 'V2T1', 'V2T2')

def enums(text):
    result = {}
    for m in re.finditer(r'enum class (\w+)\s*:\s*\w+\s*\{([^}]+)\}', text):
        entries = []
        for x in re.finditer(r'(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*,?', m[2]):
            entries.append({'symbol': x[1], 'value': int(x[2], 0), 'hex': f'0x{int(x[2],0):02X}'})
        result[m[1]] = {'line': text.count('\n', 0, m.start()) + 1, 'entries': entries}
    return result

def structures(text):
    for m in re.finditer(r'\bstruct (\w+)\s*\{', text):
        depth, pos = 1, m.end()
        while depth and pos < len(text):
            depth += (text[pos] == '{') - (text[pos] == '}')
            pos += 1
        body = text[m.end():pos-1]
        preceding = text[max(0,m.start()-150):m.start()]
        anchor = re.search(r'//\s*(THMSGV\w+)\s*$', preceding)
        commands = re.findall(r'Command\s+\w+\{Command::(\w+)\}', body)
        selectors = re.findall(r'(\w*InquiredType)\s+\w+\{(?:\w+::)?\1::(\w+)\}', body)
        if not selectors:
            selectors = re.findall(r'(\w*InquiredType)\s+\w+\{[^}]*?::(\w+)\}', body)
        fields = []
        for line in body.splitlines():
            f = re.search(r'^\s*([^/;]+?)\s+(\w+)(?:\{[^}]*\})?;\s*//\s*(0x[0-9A-Fa-f]+)', line)
            if f:
                fields.append({'name': f[2], 'type': f[1].strip(), 'offset': int(f[3],16), 'default': re.search(r'\{([^}]*)\}', line)[1] if re.search(r'\{([^}]*)\}', line) else None})
        yield {'name':m[1], 'ipa_class':anchor[1] if anchor else None,
               'line':text.count('\n',0,m.start())+1, 'commands':commands,
               'selectors':selectors, 'fields':fields,
               'serialization':'custom' if 'EXTERN_SERIALIZATION' in body else 'fixed_or_generated'}

def policy(symbol, subsystem):
    s = symbol.upper()
    if subsystem in ('Updt', 'Update') or 'FW_UPDATE' in s or 'FIRMWARE_UPDATE' in s:
        return 'firmware_updater_excluded'
    if 'ACCOUNT' in s or 'CLOUD' in s:
        return 'account_cloud_excluded'
    if any(x in s for x in ('FOR_ANDROID','CONCIERGE','TUTORIAL','SONY_VOICE_ASSISTANT','SETUP_LINK','QUICK_ACCESS','AUTO_PLAY','SAR','HEART_RATE_PROFILE')):
        return 'phone_or_service_dependency'
    if subsystem in ('Log','Connect','LinkControl','TestCommand'):
        return 'protocol_or_telemetry'
    return 'headphone_control'

def generate(reference=REFERENCE, anchors_path=None):
    anchors={}
    if anchors_path and anchors_path.exists():
        a=json.loads(anchors_path.read_text())
        for c in a['classes']:
            anchors.setdefault(c['class'],[]).extend(c['methods'])
    protocols=[]; controls=[]; functions=[]; hashes={}
    for schema in SCHEMAS:
        filename='Protocol'+schema+'.hpp';path=reference/filename;text=path.read_text();e=enums(text)
        hashes[filename]=hashlib.sha256(path.read_bytes()).hexdigest()
        contracts=[]
        for st in structures(text):
            st['source']={'path':filename,'line':st.pop('line')}
            st['opcode_values']=[dict(symbol=n,value=next((x['value'] for x in e.get('Command',{}).get('entries',[]) if x['symbol']==n),None)) for n in st['commands']]
            st['ipa_anchors']=[{'selector':m['selector'],'address':m['address']} for m in anchors.get(st['ipa_class'],[]) if m['selector']!='__metadata']
            st['evidence_level']='reference_layout_and_ipa_class' if st['ipa_anchors'] else 'reference_declared_layout'
            contracts.append(st)
        protocol={'id':schema.lower(),'frame_type':12 if schema.endswith('T1') else 14,
                  'source':filename,'enums':e,'contracts':contracts}
        protocols.append(protocol)
        for name, enum in e.items():
            if name=='FunctionType':
                for entry in enum['entries']:
                    functions.append(dict(entry, protocol=schema.lower(),category=policy(entry['symbol'],''),source={'path':filename,'line':enum['line']}))
            if not name.endswith('InquiredType'):continue
            subsystem=name[:-len('InquiredType')]
            for entry in enum['entries']:
                if entry['symbol'] in ('NO_USE','OUT_OF_RANGE','UNKNOWN','NONE'):continue
                relevant=[c for c in contracts if [name,entry['symbol']] in [list(v) for v in c['selectors']]]
                # Common base serializers carry a selector dynamically; preserve them
                # separately and do not pretend their default covers every enum value.
                explicit_writers=[c['name'] for c in relevant if any('_SET_' in o or o.startswith('SET_') for o in c['commands'])]
                controls.append({'id':schema.lower()+'.'+name+'.'+entry['symbol'],
                    'protocol':schema.lower(),'subsystem':subsystem,'selector_enum':name,**entry,
                    'category':policy(entry['symbol'],subsystem),
                    'implementation':'catalogued_not_implemented',
                    'contracts':[c['name'] for c in relevant], 'declared_writers':explicit_writers,
                    'source':{'path':filename,'line':enum['line']},
                    'evidence_level':'reference_layout_and_ipa_class' if any(c['ipa_anchors'] for c in relevant) else 'reference_declared_identifier'})
    # V2 support identifiers live in the shared header, scoped explicitly to t1/t2.
    p=reference/'ProtocolV2.hpp';text=p.read_text();hashes[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
    for table in (1,2):
        part=re.search(r'namespace t'+str(table)+r'\s*\{(.*?)\}\s*// namespace t'+str(table),text,re.S)
        if not part:raise ValueError('Missing V2 table support enum')
        enum=enums(part[1])['FunctionType']
        for entry in enum['entries']:
            functions.append(dict(entry,protocol='v2t'+str(table),category=policy(entry['symbol'],''),
                             source={'path':p.name,'line':text.count('\n',0,part.start(1))+enum['line']}))
    # These three core capabilities were demonstrated against the user's hardware.
    for c in controls:
        if c['protocol']=='v2t1' and (c['selector_enum'],c['symbol']) in (
          ('PowerInquiredType','LEFT_RIGHT_BATTERY'),('PowerInquiredType','CRADLE_BATTERY'),
          ('EqEbbInquiredType','PRESET_EQ'),('NcAsmInquiredType','MODE_NC_ASM_AUTO_NC_MODE_SWITCH_AND_ASM_SEAMLESS')):
            c['implementation']='implemented_hardware_verified_wf1000xm4'
    return {'schema_version':1,'reference':{'repository':'https://github.com/mos9527/SonyHeadphonesClient','commit':COMMIT,'license':'MIT','header_sha256':hashes},
            'semantics':{'catalogued':'A decoded protocol declaration, not an implemented or universally supported app control.',
                         'support_function':'An advertised device capability identifier; distinct from command opcode and inquiry.',
                         'ipa_class':'Metadata corroboration; exact packet layouts require reviewed assembly or hardware evidence.',
                         'availability':'Controls must require advertised capability, current availability, validated typed payload, and confirmed readback. Never transmit arbitrary catalogue-derived SET packets.'},
            'protocols':protocols,'shared_enums':{v.lower():enums((reference/('Protocol'+v+'.hpp')).read_text()) for v in ('V1','V2')},'support_functions':functions,'controls':controls,
            'excluded_services':['Sony Account','Cloud services','Firmware updater'],
            'app_local_candidates':[{'feature':'Adaptive Sound Control location/activity rules','category':'platform_local','status':'not_implemented','evidence':'HPC/Swift ASC metadata; phone location/activity semantics require an independent macOS policy engine.'},
                                    {'feature':'Ear-tip fit and wearing guidance','category':'phone_or_local_dependency','status':'not_implemented','evidence':'Earpiece-selection and wearing-test protocol declarations; actual audio assay requires model capabilities and runtime validation.'}]}

def write_summary(catalog, output):
    from collections import Counter
    counts=Counter(c['subsystem'] for c in catalog['controls'])
    lines=['# Feature coverage','',
      'The inventory is generated from four pinned protocol headers and matched Sound Connect 13.2.0 Objective-C metadata. It inventories device-control declarations, not all app imports or marketing features. Catalogue coverage and implemented controls are separate.', '',
      f"{len(catalog['controls'])} inquiry declarations, {len(catalog['support_functions'])} advertised function identifiers, and {sum(len(p['contracts']) for p in catalog['protocols'])} packet contracts are recorded in `feature-catalog.json`.",'',
      '| Subsystem | Inquiry declarations | Coverage |','|---|---:|---|']
    for subsystem,n in sorted(counts.items()):
        state='Excluded: firmware updater' if subsystem in ('Updt', 'Update') else 'Protocol catalogue; implementation varies by typed handler and device capability'
        if subsystem in ('Power','Battery','NcAsm','EqEbb'):state='Core battery / ANC / EQ paths implemented; WF-1000XM4 core paths verified'
        lines.append(f'| {subsystem} | {n} | {state} |')
    lines += ['', 'The app must select protocol version, table, advertised function, and availability before reading or writing a control. An ACK alone never proves a setting changed. Core readback fixtures come from WF-1000XM4 firmware 2.3.1; other models are untested.', '',
              'Sony Account, cloud services, and firmware updating are excluded. Voice-assistant provider setup, Quick Access integrations, phone activity/location rules, audio rendering, and LE Audio profile management require additional host or service work. Hardware declarations for these remain catalogued so missing work is visible.', '',
              'All inquiry rows begin as `catalogued_not_implemented`; only narrowly established core fields are marked hardware verified. New application handlers must be reported separately and tested before changing this status. See `DEVICE_SUPPORT.md` for the support boundary and `REVERSE_ENGINEERING.md` for evidence limitations.']
    output.write_text('\n'.join(lines)+'\n')

def control_descriptors(catalog):
    result=[]
    for protocol in catalog['protocols']:
        enum_map=protocol['enums']
        for contract in protocol['contracts']:
            if not any('_SET_' in n or n.startswith('SET_') for n in contract['commands']):continue
            if not contract['selectors']:continue
            selector_name,selector_symbol=contract['selectors'][0]
            row=next((c for c in catalog['controls'] if c['protocol']==protocol['id'] and c['selector_enum']==selector_name and c['symbol']==selector_symbol),None)
            if not row:continue
            fields=[];fixed=True
            for field in contract['fields']:
                if field['offset']<2:continue
                typ=field['type'].strip()
                entries=enum_map.get(typ,{}).get('entries',[])
                if not entries:
                    shared=catalog['shared_enums'].get(protocol['id'][:2],{})
                    entries=shared.get(typ,{}).get('entries',[])
                options=[{'value':e['value'],'label':e['symbol'].replace('_',' ').capitalize()} for e in entries if e['symbol'] not in ('OUT_OF_RANGE','UNKNOWN','UNSPECIFIED','NO_USE')]
                width={'UInt8':1,'Int8':1,'UInt16':2,'Int16':2,'UInt32':4,'Int32':4,'bool':1}.get(typ,1 if entries else None)
                if width is None:fixed=False
                fields.append({'key':field['name'],'title':re.sub(r'(?<!^)(?=[A-Z])',' ',field['name']).capitalize(),
                  'offset':field['offset'],'width':width,'kind':'choice' if options else 'capability_number' if width else 'structured',
                  'options':options,'reference_default':field['default'],
                  'editable':bool(options), 'reason':None if options else 'Device capability range or structured handler required'})
            partner_name=contract['name'].replace('Set','Ret',1)
            partner=next((c for c in protocol['contracts'] if c['name']==partner_name),None)
            partner_fields=partner['fields'] if partner else []
            exact_partner=bool(partner) and [(f['offset'],f['type']) for f in contract['fields']] == [(f['offset'],f['type']) for f in partner_fields]
            command_entries=enum_map.get('Command',{}).get('entries',[])
            set_symbol=contract['commands'][0]
            get_symbol=set_symbol.replace('_SET_','_GET_').replace('SET_','GET_',1)
            get_opcode=next((e['value'] for e in command_entries if e['symbol']==get_symbol),None)
            item={'id':protocol['id']+'.'+contract['name'],'title':row['symbol'].replace('_',' ').capitalize(),
              'group':row['subsystem'],'protocol':protocol['id'],'frame_type':protocol['frame_type'],
              'inquiry':row['value'],'set_opcode':contract['opcode_values'][0]['value'],
              'reply_opcode':partner['opcode_values'][0]['value'] if partner and partner['opcode_values'] else None,
              'get_opcode':get_opcode,'set_contract':contract['name'],'readback_contract':partner_name if partner else None,
              'fields':fields,'packet_size':max((f['offset']+(f['width'] or 0) for f in fields),default=2) if fixed else None,
              'category':row['category'],'metadata_correlated':bool(contract['ipa_anchors']),
              'fixed_layout':fixed and contract['serialization']=='fixed_or_generated',
              'exact_readback_layout':exact_partner,
              'enabled':False,
              'reason':'Requires exact advertised-function binding, current readback, device capabilities, availability and typed handler validation',
              'source':contract['source']}
            # This is a declaration-backed descriptor, never automatic mutation authority.
            result.append(item)
    return {'schema_version':1,'reference_commit':catalog['reference']['commit'],
      'safety_contract':'All descriptors disabled by default. Never transmit catalogue-derived bytes without a reviewed capability binding and a confirmed current readback. Preserve unchanged fields; validate enum choices/ranges; require readback after SET. Custom/variable layouts require explicit typed codecs.',
      'controls':result}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference',type=Path,default=REFERENCE)
    parser.add_argument('--ipa-anchors',type=Path,default=ROOT/'docs/ipa-protocol-provenance.json')
    parser.add_argument('--output',type=Path,default=ROOT/'docs/feature-catalog.json')
    parser.add_argument('--check',action='store_true',help='Check generated bytes without modifying outputs')
    args=parser.parse_args();catalog=generate(args.reference,args.ipa_anchors)
    payload=json.dumps(catalog,indent=2,ensure_ascii=True)+'\n'
    if args.check:
        if not args.output.exists() or args.output.read_text()!=payload:raise SystemExit('Feature catalogue is stale; regenerate it.')
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(payload);write_summary(catalog,args.output.parent/'PROTOCOL_INVENTORY.md'); (args.output.parent/'control-descriptors.json').write_text(json.dumps(control_descriptors(catalog),indent=2)+'\n'); (args.output.parent/'feature-catalog-ui.json').write_text(json.dumps({'schema_version':1,'controls':[{'id':c['id'],'title':c['symbol'].replace('_',' ').capitalize(),'group':c['subsystem'],'status':c['implementation'],'category':c['category'],'reason':'Additional typed handler and model validation required' if c['implementation']=='catalogued_not_implemented' else None} for c in catalog['controls']]},indent=2)+'\n')
    print(f"{len(catalog['controls'])} inquiries; {len(catalog['support_functions'])} support identifiers; {sum(len(p['contracts']) for p in catalog['protocols'])} packet contracts")
if __name__=='__main__':main()
