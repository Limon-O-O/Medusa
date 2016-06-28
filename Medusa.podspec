Pod::Spec.new do |s|

  s.name        = "Medusa"
  s.version     = "0.2"
  s.summary     = "Video recorder."

  s.description = <<-DESC
                    A Video Recorder for the Zodio iPhone app.
                  DESC

  s.homepage    = "https://github.com/Limon-O-O/Medusa"

  s.license     = { :type => "MIT", :file => "LICENSE" }

  s.authors           = { "Limon" => "fengninglong@gmail.com" }
  s.social_media_url  = "https://twitter.com/Limon______"

  s.ios.deployment_target   = "8.0"
  # s.osx.deployment_target = "10.7"

  s.source          = { :git => "https://github.com/Limon-O-O/Medusa.git", :tag => s.version }
  s.source_files    = "Medusa/*.swift"
  s.requires_arc    = true

end
