!  9"	1�	�SuperSUB V1.1
$�	:] � ʛ� �q�h�@������  !e ~� �U	�;¹��!	�_�~#�_�!� ͟2e��/#"b~2d� �#�x~#��� ʔ�	͟�ͱ�Ô~#�7�� ʟ�	ʟ+���*T�*V~���s#r#"V�� ~#���� ���	�����"T�p�7�?�!  "X:e�/�\ � <ʹ*X#"X*Z�*T"Zs#r#�# �Q�K͂��K�
���Cw#�����"T�q�"T�q����:e�/�b͎�z:a���n_ <2a!� ~����\ � �> 7�?�:d�¬:����ک=2��>�>�*b~#"b�;¼>ɷ�>�m	� �
� :�!�"b�7�?�: =��ê
	� <��:	2*	�
	� <ʘ�*Z|��	^#V#�"Z�~��9*X+"X�*Z|��F^#V#�"Z��N*X+"X�(
	� ~#2\"]!� "_�2� Ew#�a�����^����@�� ��$:e�/>$ʟ����$¥����g�E�� ü����E�����0Ox�����Gðx=��� ��G�g~#�����
	� ��!\~=7�w*]~#"]?�!� 4��*_w#"_�:\�7�~?��
��o& )f^#Vz��7���~#���#�;��0��:?��������	�U
 	�|��L{�0�u����>�u>
���_� �����a��{��_��3Disk full$�3Directory full$�3Memory full$�3Submit file not found$�3Parameter$�3Too many parameters:$�3Line too long:$�3Submit file empty$�3Control character$�	� U	� *X�L�n
	� �   error on line number: $
*$!T2 6 #x��w!f"V!��"�!�	"T>�2a2���	� *	��
How to use SUPERSUB:

SUPERSUB<CR>		:print this HELP message
SUPERSUB /<CR>		:go into interactive mode
SUPERSUB /<cmd lines>	:use SUMMARY mode
SUPERSUB <FILE> <PARMS>	:as in standard SUBMIT.COM

IN "/" (interactive) mode, SUPERSUB will prompt you
a line at a time for the SUBMIT job input...logical
lines may be combined on the same input line by sep-
erating them with semicolons.  Example:
   A>SUPERSUB /STAT;DIR
specifies two commands on the same input line.

Submitted jobs may be nested...SUPERSUB does not erase
any existing submit job (appends to them instead).

To insert a control character into the output, pre-
fix it with a "^" (works in any mode).
$                  mmands on the same input line.  � Submitted jobs may be nested...SUPERSUB does not erase
any existing submit job (appends to them instead).

To insert a contro  $$$     SUB                                                                                                          