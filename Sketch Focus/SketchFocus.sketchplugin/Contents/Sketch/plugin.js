function showWindowHandler(context) {
    if(!loadFramework(context)) return;
    SketchFocus.showWindow();
}

function loadFramework(context) {
    if(NSClassFromString('SketchFocus') != null) return true;
    var pluginBundle = NSBundle.bundleWithURL(context.plugin.url());
    var mocha = Mocha.sharedRuntime();
    return mocha.loadFrameworkWithName_inDirectory("SketchFocus", pluginBundle.resourceURL().path());
}
