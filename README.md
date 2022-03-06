# aseprite-custombrushoptions

![ezgif com-gif-maker(1)](https://user-images.githubusercontent.com/5313706/156926743-f9d3f31d-2ddc-4a82-9096-5ad9c4799c88.gif)

A script for aseprite that adds some additional functions to custom brushes. Note that in the above gif I'm using an auto clicker macro in addition to the script to mimic the spray can tool (But with randomized brush images). 

**HOW TO USE**

1. In aseprite, go File->Scripts->Open scripts folder
2. Download the zip file. Put CustomBrushOptions.lua into the scripts folder.
3. File->Scripts->Rescan scripts folder
4. File->Scripts->CustomBrushOptions
5. Should be good to go!

**BRUSH FROM SELECTION**

To use brushes from selection, you need to make multiple selections with the rectangular marquee tool. The selections should have at least a 1px margin from each other so that they register as separate brushes. Then, press "Brushes from selection" and now every time you click the brush will change. 

You can also check "Randomize brush order" to randomize which brush gets selected.

NOTE: Unfortunately multiple brushes won't work with the spray can tool :(
