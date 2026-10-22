import SwiftUI
import WidgetKit

@main struct HorizonWidgets: WidgetBundle {
    var body: some Widget {
        HorizonLiveActivity()
        HorizonConnectionWidget()
        HorizonConnectionControl()
    }
}
