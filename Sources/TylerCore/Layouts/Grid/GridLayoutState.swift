package struct GridLayoutState: LayoutState {
  package internal(set) var weights: ColumnWeights

  package init() {
    self.init(weights: ColumnWeights())
  }

  package init(weights: ColumnWeights) {
    self.weights = weights
  }
}
