# Pull the parser and compiler out of the prototype page into engine.js so node can test them.
import os
here = os.path.dirname(os.path.abspath(__file__))
s = open(os.path.join(here, "..", "ability-blocks-stack.html"), encoding="utf-8").read()
js = s[s.index("<script>") + 8:]
js = js[:js.index("/* =====================================================================\n   Rendering: the stack")]
open("engine.js", "w").write(js + "\nmodule.exports={parseGS,printAst,astToX,holderFromText,cHolder,DOCS,norm,get problems(){return problems},reset(){problems=[]}};\n")
