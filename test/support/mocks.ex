defmodule Gremlex.Test.Mocks do
  def vertex do
    %{
      "id" => %{
        "@type" => "g:Int32",
        "@value" => 1
      },
      "label" => "person",
      "properties" => %{
        "name" => [
          %{
            "@type" => "g:VertexProperty",
            "@value" => %{
              "id" => %{
                "@type" => "g:Int64",
                "@value" => 0
              },
              "value" => "marko",
              "vertex" => %{
                "@type" => "g:Int32",
                "@value" => 1
              },
              "label" => "name"
            }
          }
        ],
        "location" => [
          %{
            "@type" => "g:VertexProperty",
            "@value" => %{
              "id" => %{
                "@type" => "g:Int64",
                "@value" => 6
              },
              "value" => "san diego",
              "vertex" => %{
                "@type" => "g:Int32",
                "@value" => 1
              },
              "label" => "location",
              "properties" => %{
                "startTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 1997
                },
                "endTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2001
                }
              }
            }
          },
          %{
            "@type" => "g:VertexProperty",
            "@value" => %{
              "id" => %{
                "@type" => "g:Int64",
                "@value" => 7
              },
              "value" => "santa cruz",
              "vertex" => %{
                "@type" => "g:Int32",
                "@value" => 1
              },
              "label" => "location",
              "properties" => %{
                "startTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2001
                },
                "endTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2004
                }
              }
            }
          },
          %{
            "@type" => "g:VertexProperty",
            "@value" => %{
              "id" => %{
                "@type" => "g:Int64",
                "@value" => 8
              },
              "value" => "brussels",
              "vertex" => %{
                "@type" => "g:Int32",
                "@value" => 1
              },
              "label" => "location",
              "properties" => %{
                "startTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2004
                },
                "endTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2005
                }
              }
            }
          },
          %{
            "@type" => "g:VertexProperty",
            "@value" => %{
              "id" => %{
                "@type" => "g:Int64",
                "@value" => 9
              },
              "value" => "santa fe",
              "vertex" => %{
                "@type" => "g:Int32",
                "@value" => 1
              },
              "label" => "location",
              "properties" => %{
                "startTime" => %{
                  "@type" => "g:Int32",
                  "@value" => 2005
                }
              }
            }
          }
        ]
      }
    }
  end

  def vertex_property do
    %{
      "id" => %{
        "@type" => "g:Int64",
        "@value" => 0
      },
      "value" => "marko",
      "vertex" => %{
        "@type" => "g:Int32",
        "@value" => 1
      },
      "label" => "name"
    }
  end

  def vertex_property_no_vertex do
    %{
      "id" => %{
        "@type" => "g:Int64",
        "@value" => 0
      },
      "value" => "marko",
      "label" => "name"
    }
  end

  def map() do
    [
      %{
        "@type" => "g:T",
        "@value" => "label"
      },
      "LABEL_1",
      "created_at",
      %{
        "@type" => "g:List",
        "@value" => [
          %{
            "@type" => "g:Date",
            "@value" => 1_557_753_523_490
          }
        ]
      },
      %{
        "@type" => "g:T",
        "@value" => "id"
      },
      "VERTEX_1",
      "prop1",
      %{
        "@type" => "g:List",
        "@value" => [
          false
        ]
      }
    ]
  end

  def map_with_int_as_vertex_id() do
    [
      %{
        "@type" => "g:T",
        "@value" => "label"
      },
      "LABEL_1",
      "created_at",
      %{
        "@type" => "g:List",
        "@value" => [
          %{
            "@type" => "g:Date",
            "@value" => 1_557_753_523_490
          }
        ]
      },
      %{
        "@type" => "g:T",
        "@value" => "id"
      },
      %{
        "@type" => "g:Int32",
        "@value" => 1
      },
      "prop1",
      %{
        "@type" => "g:List",
        "@value" => [
          false
        ]
      }
    ]
  end

  def path() do
    %{
      "labels" => %{
        "@type" => "g:List",
        "@value" => [
          %{
            "@type" => "g:Set",
            "@value" => []
          },
          %{
            "@type" => "g:Set",
            "@value" => []
          }
        ]
      },
      "objects" => %{
        "@type" => "g:List",
        "@value" => [
          %{
            "@type" => "g:Vertex",
            "@value" => %{
              "id" => "VERTEX_1",
              "label" => "LABEL_1"
            }
          },
          %{
            "@type" => "g:Vertex",
            "@value" => %{
              "id" => "VERTEX_2",
              "label" => "LABEL_1"
            }
          }
        ]
      }
    }
  end
end
