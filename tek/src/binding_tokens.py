"""TEAP v3 BindingToken16 codec. Schema 1 is intentionally whitelist-only."""
from __future__ import annotations
from dataclasses import dataclass

class BindingTokenError(ValueError): pass

KEYS = {
    1:'Q',2:'E',3:'R',4:'F',5:'1',6:'2',7:'3',8:'4',9:'5',10:'Z',11:'X',12:'C',13:'V',14:'T',15:'G',
    16:'F1',17:'F2',18:'F3',19:'F4',20:'`',21:'MOUSEWHEELUP',22:'MOUSEWHEELDOWN',23:'BUTTON3'
}
KEY_TO_CODE={v:k for k,v in KEYS.items()}
MODIFIERS={0:'',1:'ALT',2:'CTRL'}
MOD_TO_CODE={v:k for k,v in MODIFIERS.items()}
KINDS={0:'keyboard',1:'wheel',2:'mouse'}

@dataclass(frozen=True)
class BindingToken:
    token:int
    binding:str
    key:str
    modifier:str
    input_type:str

def decode_binding_token(token:int)->BindingToken:
    token=int(token)
    if token <= 0 or token > 0xFFFF: raise BindingTokenError(f'invalid_token:{token}')
    key_code=token & 0x3F; modifier_code=(token>>6)&0x0F; type_code=(token>>10)&0x03
    key=KEYS.get(key_code); modifier=MODIFIERS.get(modifier_code); input_type=KINDS.get(type_code)
    if not key or modifier is None or not input_type: raise BindingTokenError(f'unsupported_token:{token}')
    if input_type != 'keyboard' and modifier: raise BindingTokenError('mouse_modifier_unsupported')
    if input_type=='wheel' and key not in ('MOUSEWHEELUP','MOUSEWHEELDOWN'): raise BindingTokenError('wheel_token_mismatch')
    if input_type=='mouse' and key!='BUTTON3': raise BindingTokenError('mouse_token_mismatch')
    return BindingToken(token=token,binding=f'{modifier}+{key}' if modifier else key,key=key,modifier=modifier,input_type=input_type)

def encode_binding_token(binding:str)->int:
    raw=str(binding).upper().replace('-','+')
    parts=[x for x in raw.split('+') if x]
    modifier=''
    if len(parts)==2 and parts[0] in ('ALT','CTRL'): modifier=parts.pop(0)
    if len(parts)!=1: raise BindingTokenError('invalid_binding')
    key=parts[0]; code=KEY_TO_CODE.get(key)
    if not code: raise BindingTokenError(f'unsupported_key:{key}')
    input_type=1 if key.startswith('MOUSEWHEEL') else 2 if key=='BUTTON3' else 0
    if input_type and modifier: raise BindingTokenError('mouse_modifier_unsupported')
    return code | (MOD_TO_CODE[modifier]<<6) | (input_type<<10)
