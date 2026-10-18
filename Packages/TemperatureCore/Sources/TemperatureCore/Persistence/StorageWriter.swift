struct StorageWriter {
    let maxOldestAgeMS: Int
    var pausedForTesting = false

    init(configuration: RuntimeConfiguration) {
        maxOldestAgeMS = configuration.writerMaxOldestAgeMS
    }
}
